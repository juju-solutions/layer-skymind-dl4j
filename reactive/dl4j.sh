#!/bin/bash
set -ex

source charms.reactive.sh

# 'apt.installed.cmake' 'apt.installed.maven3'
@when_not 'dl4j.installed' 
@when 'cuda.available' 
function install_dl4j() {
    status-set maintenance "Installing dl4j software"

    juju-log "Installing dependencies"
    # Note most deps are installed from the layer.yaml options
    # Then the rest from the apt layer

    # We need maven 3.2.3+ which is not in repos. Installing if necessary
    hash mvn 2>/dev/null || apt-get remove --purge maven 

    add-apt-repository -y ppa:george-edison55/cmake-3.x
    apt-add-repository -y ppa:andrei-pozolotin/maven3
    apt-add-repository -y ppa:openjdk-r/ppa
    apt-add-repository -y ppa:jochenkemnade/openjdk-8

    apt-get update -yqq && \
    apt-get install -yqq \
        cmake \
        maven3 \
        openjdk-8-jre-headless \
        openjdk-8-jdk

    case "$(arch)" in 
        "x86_64" | "amd64" )
            apt-get install -yqq libopenblas-base libopenblas-dev
        ;;
        "ppc64le" )
            git clone https://github.com/xianyi/OpenBLAS.git /mnt/openblas
            cd /mnt/openblas
            make && make PREFIX=/usr install
        ;;
        "*" )
            juju-log "Your architecture is not supported yet. Exiting"
            exit 1
        ;;
    esac


    juju-log "Creating program variables"
    export LIBND4J_HOME="/mnt/libnd4j"
    echo 'export LIBND4J_HOME="/mnt/libnd4j"' | tee /etc/profile.d/libnd4j.sh
    chmod +x /etc/profile.d/libnd4j.sh

    juju-log "Downloading required projects"
    for PROJECT in nd4j libnd4j deeplearning4j Canova
    do
        [ -d "/mnt/${PROJECT}" ] \
            || git clone -q https://github.com/deeplearning4j/${PROJECT}.git "/mnt/${PROJECT}" \
            && { cd "/mnt/${PROJECT}" ; git pull origin master ; cd - ; }
    done 
    
    [ -d "/mnt/javacpp" ] \
        || git clone -q https://github.com/bytedeco/javacpp.git /mnt/javacpp \
        && { cd "/mnt/javacpp" ; git pull origin master ; cd - ; }

    juju-log "Installing Java CPP"
    cd /mnt/javacpp
    mvn clean install -DskipTests

    juju-log "Installing libnd4j for CPU & GPU"
    cd ${LIBND4J_HOME}
    for TARGET in cpu cuda
    do
        ./buildnativeoperations.sh blas ${TARGET}
    done 

    juju-log "Installing DL4j"
    for PROJECT in nd4j deeplearning4j Canova
    do
        cd "/mnt/${PROJECT}"
        JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64" mvn clean install -DskipTests -Dmaven.javadoc.skip=true
    done

    charms.reactive set_state 'dl4j.installed'
}

@when 'dl4j.installed'
@when_not 'dl4j.available'
function start_dl4j() {
    status-set active "dl4j installed and ready"
    charms.reactive set_state 'dl4j.available'
}

reactive_handler_main
