#!/bin/bash -e


snap_taf_install_prerequisites()
{
  if [ ! -e "./edgex-taf-common" ]; then
        sudo apt-get install python-is-python3
        sudo apt-get install python3-pip
        git clone https://github.com/edgexfoundry/edgex-taf-common.git
        ## Install dependency lib
        pip3 install -r ./edgex-taf-common/requirements.txt
        ## Install edgex-taf-common as lib
        pip3 install ./edgex-taf-common
    else
        >&2 echo "INFO:snap: TAF prerequisites already installed"
    fi 


} 
 
snap_taf_enable_snap_testing() 
{

    # modify `TAF/config/global_variables.py`
    sed -i -e 's@"docker"@"snap"@' $WORK_DIR/TAF/config/global_variables.py

    # modify commonKeywords.robot
    sed -i -e 's@docker exec edgex-core-consul cat /tmp/edgex/secrets/@cat /var/snap/edgexfoundry/current/secrets/@' $WORK_DIR/TAF/testCaseModules/keywords/common/commonKeywords.robot

    # modify POST.robot
    sed -i -e 's@docker exec edgex-${app_service_name} cat /tmp/edgex/secrets@cat /var/snap/edgex-app-service-configurable/current@' $WORK_DIR/TAF/testScenarios/functionalTest/V2-API/app-service/secrets/POST.robot

    # modify APPServiceAPI.robot
    sed -i -e ':a;N;$!ba;s@:\n    Check@:\n    Set Environment Variable  SNAP_APP_SERVICE_PORT  ${port}[2]\n    Check@' $WORK_DIR/TAF/testCaseModules/keywords/app-service/AppServiceAPI.robot
   

    # modify TAF/testCaseModules/keywords/setup/edgex.py 
    sed -i -e "s!\"docker logs edgex-{} --since {}\".format(service, timestamp)!\"journalctl -g {} -S @{}\".format(service.replace(\'app-\',\'\'),timestamp)!" $WORK_DIR/TAF/testCaseModules/keywords/setup/edgex.py
   
   # modify TAF/testCaseModules/keywords/setup/startup_checker.py 
    sed -i -e 's!"docker logs {}"!"journalctl -g {}"!' $WORK_DIR/TAF/testCaseModules/keywords/setup/startup_checker.py

    # update host name
    sed -i -e 's@Host=edgex-support-scheduler@Host=localhost@' $WORK_DIR/TAF/testScenarios/functionalTest/V2-API/support-scheduler/intervalaction/POST-Positive.robot

    # this test assumes we are running on two different IP addresses. Set DOCKER_IP to an invalid IP in this case as otherwise we get duplicate transmissions
    sed -i -e 's@${DOCKER_HOST_IP}@"invalid-ip"@' $WORK_DIR/TAF/testScenarios/functionalTest/V2-API/support-notifications/transmission/GET-Positive.robot

   # integration tests
   # The notification sender is "core-metadata", not "edgex-core-metadata"
    sed -i -e 's@edgex-core-metadata@core-metadata@' $WORK_DIR/TAF/testScenarios/integrationTest/UC_metadata_notifications/metadata_notifications.robot

    # in case python2 is the default, replace it with python3 (can also be done by apt-get install python3-is-python)
    sed -s -i -e 's@Start process  python @Start process  python3 @' $WORK_DIR/TAF/testScenarios/functionalTest/V2-API/support-notifications/transmission/*.robot

    # remove system-agent tests - we don't run them because the system agent service has been deprecated since the Ireland release (2.0)
    rm -rf $WORK_DIR/TAF/testScenarios/functionalTest/V2-API/system-agent/info
    rm -rf $WORK_DIR/TAF/testScenarios/functionalTest/V2-API/system-agent/services

    
    export DOCKER_HOST_IP="localhost"

}

snap_taf_deploy_edgex()
{
   cd ${WORK_DIR}
    # 1. Deploy EdgeX
    python3 -m TUC --exclude Skipped --include deploy-base-service -u deploy.robot -p default
 
    mkdir -p "$WORK_DIR/TAF/testArtifacts/reports/cp-edgex/"
}

snap_taf_run_functional_tests() # arg:  tests to run
{
   cd ${WORK_DIR}

    # 2. Run V2 API Functional testing (using directories in TAF/testScenarios/functionalTest/V2-API )
    # 
    rm -f $WORK_DIR/TAF/testArtifacts/reports/cp-edgex/v2-api-test.html
    
    if [ "$1" = "all" ]; then  
        python3 -m TUC --exclude Skipped --include v2-api -u functionalTest/V2-API/ -p default    
        cp $WORK_DIR/TAF/testArtifacts/reports/edgex/log.html $WORK_DIR/TAF/testArtifacts/reports/cp-edgex/v2-api-test.html
        >&2 echo "INFO:snap: Test report copied to $WORK_DIR/TAF/testArtifacts/reports/cp-edgex/v2-api-test.html"
    elif [ ! -z "$1" ]; then
        python3 -m TUC --exclude Skipped --include v2-api -u functionalTest/V2-API/${1} -p default    
        cp $WORK_DIR/TAF/testArtifacts/reports/edgex/log.html $WORK_DIR/TAF/testArtifacts/reports/cp-edgex/v2-api-test.html
        >&2 echo "INFO:snap: V2 API Test report copied to $WORK_DIR/TAF/testArtifacts/reports/cp-edgex/v2-api-test.html"
    fi
  
}

snap_taf_run_functional_device_tests()
{
    export EDGEX_SECURITY_SECRET_STORE=false
    export SECURITY_SERVICE_NEEDED=false  
    
  
    # 3. Run device functional tests
    for profile in $@; do
        >&2 echo "INFO:snap: testing $profile"
        python3 -m TUC --exclude Skipped -u functionalTest/device-service -p ${profile}
        rm -f $WORK_DIR/TAF/testArtifacts/reports/cp-edgex/v2-${profile}-test.html 
        cp ${WORK_DIR}/TAF/testArtifacts/reports/edgex/log.html ${WORK_DIR}/TAF/testArtifacts/reports/cp-edgex/v2-${profile}-test.html 
        >&2 echo "INFO:snap: V2 API Device Test report copied to ${WORK_DIR}/TAF/testArtifacts/reports/cp-edgex/v2-${profile}-test.html "
    done    
}

snap_taf_run_integration_tests()
{
    rm -f $WORK_DIR/TAF/testArtifacts/reports/cp-edgex/integration-test.html 
 
    cd ${WORK_DIR}
    python3 -m TUC --exclude Skipped -u integrationTest -p device-virtual
    cp ${WORK_DIR}/TAF/testArtifacts/reports/edgex/log.html ${WORK_DIR}/TAF/testArtifacts/reports/cp-edgex/integration-test.html 
     >&2 echo "INFO:snap: V2 API Device Test report copied to ${WORK_DIR}/TAF/testArtifacts/reports/cp-edgex/integration-test.html"
 }

snap_taf_shutdown()
{
    cd ${WORK_DIR}
    python3 -m TUC --exclude Skipped --include shutdown-edgex -u shutdown.robot -p default
    >&2 echo "INFO:snap: Reports are in ${WORK_DIR}/TAF/testArtifacts/reports/cp-edgex"

}