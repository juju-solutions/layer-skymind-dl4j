#!/bin/bash
set -ex

source charms.reactive.sh

#####################################################################
#
# Simple functions
#
#####################################################################

# Install is guaranteed to run once per rootfs
function bash::lib::get_ubuntu_codename() {
    lsb_release -a 2>/dev/null | grep Codename | awk '{ print $2 }'
}

#####################################################################
#
# Prepare the machine per architecture
# 
#####################################################################

function all::all::install_prerequisites() {
    # We need maven 3.2.3+ which is not in repos. Installing if necessary
    hash mvn 2>/dev/null || apt-get remove --purge maven 

    add-apt-repository -y ppa:george-edison55/cmake-3.x
    apt-add-repository -y ppa:andrei-pozolotin/maven3
    apt-add-repository -y ppa:openjdk-r/ppa
    apt-add-repository -y ppa:jochenkemnade/openjdk-8

    apt-get update -yqq && \
    apt-get install -yqq \
        maven3 \
        openjdk-8-jre-headless \
        openjdk-8-jdk \
        rsync

    juju-log "Downloading required projects"
    for PROJECT in libnd4j nd4j deeplearning4j Canova
    do
        [ -d "/mnt/${PROJECT}" ] \
            || git clone -q https://github.com/deeplearning4j/${PROJECT}.git "/mnt/${PROJECT}" \
            && { cd "/mnt/${PROJECT}" ; git pull ; }
    done 
    
    [ -d "/mnt/javacpp" ] \
        || git clone -q https://github.com/bytedeco/javacpp.git /mnt/javacpp \
        && { cd "/mnt/javacpp" ; git pull ; }
    cd /mnt/javacpp
    MAVEN_OPTS=-Xmx2048m mvn clean install -DskipTests
}

function trusty::x86_64::install_prerequisites() {
    apt-get install -yqq \
        cmake \
        libopenblas-base \
        libopenblas-dev
}

function xenial::x86_64::install_prerequisites() {
    apt-get install -yqq \
        cmake \
        libopenblas-base \
        libopenblas-dev
}

function trusty::ppc64le::install_prerequisites() {
    cd /mnt
    wget -c https://cmake.org/files/v3.5/cmake-3.5.2.tar.gz 
    tar xfz cmake-3.5.2.tar.gz
    cd cmake-3.5.2
    ./bootstrap
    make && make install 

    [ -d "/mnt/openblas" ] \
    || git clone https://github.com/xianyi/OpenBLAS.git /mnt/openblas \
    && { cd "/mnt/openblas" ; git pull ; cd - ; }
    cd /mnt/openblas
    make && make PREFIX=/usr install
}

function xenial::ppc64le::install_prerequisites() {
    cd /mnt
    wget -c https://cmake.org/files/v3.5/cmake-3.5.2.tar.gz 
    tar xfz cmake-3.5.2.tar.gz
    cd cmake-3.5.2
    ./bootstrap
    make && make install 

    [ -d "/mnt/openblas" ] \
    || git clone https://github.com/xianyi/OpenBLAS.git /mnt/openblas \
    && { cd "/mnt/openblas" ; git pull ; cd - ; }
    cd /mnt/openblas
    make && make PREFIX=/usr install
}

#####################################################################
#
# Install libnd4j per architecture
# 
#####################################################################

function trusty::x86_64::install_libnd4j() {
    export LIBND4J_HOME="/mnt/libnd4j"
    echo 'export LIBND4J_HOME="/mnt/libnd4j"' | sudo tee /etc/profile.d/libnd4j.sh

    cd ${LIBND4J_HOME}

    hash nvcc 2>/dev/null \
        && TARGET_LIST="cpu cuda" \
        || TARGET_LIST="cpu" \

    for TARGET in ${TARGET_LIST}
    do
        [ -f "~/.built_libnd4j_${TARGET}" ] || \
            { ./buildnativeoperations.sh blas ${TARGET} \
                && touch "~/.built_libnd4j_${TARGET}" ; }
    done 
}

function xenial::x86_64::install_libnd4j() {
    trusty::x86_64::install_libnd4j
}

function trusty::ppc64le::install_libnd4j() {
   export LIBND4J_HOME="/mnt/libnd4j"
    echo 'export LIBND4J_HOME="/mnt/libnd4j"' | sudo tee /etc/profile.d/libnd4j.sh

    cd ${LIBND4J_HOME}
    # Intentionally removing CUDA for now
    hash nvcc 2>/dev/null \
        && TARGET_LIST="cpu" \
        || TARGET_LIST="cpu" \

    for TARGET in ${TARGET_LIST}
    do
        [ -f "~/.built_libnd4j_${TARGET}" ] || \
            { ./buildnativeoperations.sh blas ${TARGET} \
                && touch "~/.built_libnd4j_${TARGET}" ; }
    done 
}

function xenial::ppc64le::install_libnd4j() {
    trusty::ppc64le::install_libnd4j
}


#####################################################################
#
# Install ND4j, DL4j, and Canova per architecture
# 
#####################################################################

function trusty::ppc64le::install_dl4j() {
    for PROJECT in nd4j deeplearning4j Canova
    do
        if [ ! -f "~/.built_${PROJECT}" ]
        then
            cd "/mnt/${PROJECT}"
            JAVA_HOME="/usr/lib/jvm/java-8-openjdk-ppc64el" mvn clean install -DskipTests -Dmaven.javadoc.skip=true \
                && touch "~/.built_${PROJECT}"
        fi 
    done
}

function trusty::x86_64::install_dl4j() {
    trusty::ppc64le::install_dl4j
}

function xenial::x86_64::install_dl4j() {
    trusty::ppc64le::install_dl4j
}

function xenial::ppc64le::install_dl4j() {
    trusty::ppc64le::install_dl4j
}

UBUNTU_CODENAME="$(bash::lib::get_ubuntu_codename)"


# 'apt.installed.cmake' 'apt.installed.maven3'
@when_not 'dl4j.installed' 
@when 'cuda.available' 
function install_dl4j() {
    status-set maintenance "Installing dl4j software"

    juju-log "Installing dependencies"
    all::all::install_prerequisites

    case "$(arch)" in 
        "x86_64" | "amd64" )
            ARCH="x86_64"
        ;;
        "ppc64le" )
            ARCH="$(arch)"
        ;;
        "*" )
            juju-log "Your architecture is not supported yet. Exiting"
            exit 1
        ;;
    esac
    ${UBUNTU_CODENAME}::${ARCH}::install_prerequisites
    
    juju-log "Installing DL4j & Other libs"
    ${UBUNTU_CODENAME}::${ARCH}::install_libnd4j
    ${UBUNTU_CODENAME}::${ARCH}::install_dl4j

    juju-log "Moving Maven Repo to /mnt/.m2 and making readable"
    rsync -autvr --delete ${HOME}/.m2 /mnt/
    chmod -R a+r /mnt/.m2

    charms.reactive set_state 'dl4j.installed'
}

@when 'dl4j.installed'
@when_not 'dl4j.available'
function start_dl4j() {
    status-set active "dl4j installed and ready"
    charms.reactive set_state 'dl4j.available'
}

reactive_handler_main
