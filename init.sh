#!/bin/bash

#-------------------------------------------------------------

base64 -d <<<"ICAgICAgICAgX25ubm5fICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgIGRHR0dHTU1iICAgICAsIiIiIiIiIiIiIiIiIiIuCiAgICAgICBAcH5xcH5+cU1iICAgIHwgTGludXggUnVsZXMhIHwKICAgICAgIE18QHx8QCkgTXwgICBfOy4uLi4uLi4uLi4uLi4uJwogICAgICAgQCwtLS0tLkpNfCAtJwogICAgICBKU15cX18vICBxS0wKICAgICBkWlAgICAgICAgIHFLUmIKICAgIGRaUCAgICAgICAgICBxS0tiCiAgIGZaUCAgICAgICAgICAgIFNNTWIKICAgSFpNICAgICAgICAgICAgTU1NTQogICBGcU0gICAgICAgICAgICBNTU1NCiBfX3wgIi4gICAgICAgIHxcZFMicU1MCiB8ICAgIGAuICAgICAgIHwgYCcgXFpxCl8pICAgICAgXC5fX18uLHwgICAgIC4nClxfX19fICAgKU1NTU1NTXwgICAuJwogICAgIGAtJyAgICAgICBgLS0nIGhqbQ=="
echo ""

ROOT_DIR=~/cmsbuild
BOOTSTRAP=0
RUN_IMAGE=0
FORCE_BUILD=0
SCRAM_ARCH=slc7_amd64_gcc700
CMS_DIST="https://github.com/cms-sw/cmsdist"

#-------------------------------------------------------------

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -i|--root-dir)
    ROOT_DIR="$2"
    shift # past argument
    shift # past value
    ;;
    -b|--bootstrap)
    BOOTSTRAP=1
    shift # past argument
    # shift # past value
    ;;
    -f|--force)
    FORCE_BUILD=1
    shift # past argument
    ;;
    -r|--run)
    RUN_IMAGE=1
    shift # past argument
    ;;
    -a|--arch)
    SCRAM_ARCH="$2"
    shift # past argument
    shift # past value
    ;;
    -c|--cmsdist)
    CMS_DIST="$2"
    shift # past argument
    shift # past value
    ;;
    -h|--help)
    echo "-------------------------------------"
    echo "--------------- HELP ----------------"
    echo "-------------------------------------"
    echo "commands:"
    echo "-i, --root-dir: the location where the build happens"
    echo "-a, --arch: build architecture"
    echo "-b, --bootstrap: use CMSSW bootstraper."
    echo "-r, --run: run Docker Image."
    echo "-f, --force: force build."
    echo "-c, --cmsdist: CMSSW build configuration web URL"
    echo "-h, --help: display help page."
    exit 0;
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

#-------------------------------------------------------------

# -- script options --
BUILD_DIR=$ROOT_DIR/build
HOME_DIR=$ROOT_DIR/home

if [ ! -d "$ROOT_DIR" ]; then
    mkdir $ROOT_DIR
    sudo chmod 777 $ROOT_DIR
    mkdir $BUILD_DIR
    sudo chmod 777 $BUILD_DIR
    mkdir $HOME_DIR
    sudo chmod 777 $HOME_DIR
fi

# -- docker options --
DOCKER_VOLUMES="-v $BUILD_DIR:/build -v $HOME_DIR:/home/cmsbuild"
DOCKER_PORT=7777

#-------------------------------------------------------------

export_enviroment(){

    echo "
ROOT_DIR=$ROOT_DIR
BOOTSTRAP=$BOOTSTRAP
RUN_IMAGE=$RUN_IMAGE
FORCE_BUILD=$FORCE_BUILD
CMS_DIST=\"$CMS_DIST\"
export SCRAM_ARCH=$SCRAM_ARCH

alias ll=\"ls -l\"

source cmsset_default.sh
" > $BUILD_DIR/env.sh

} 

#-------------------------------------------------------------

if [ ! -d "$ROOT_DIR/cms-docker" ]; then
    if [ -d "./cms-docker" ]; then
        echo "Copying ./cms-docker -> $ROOT_DIR ..."
        cp -r ./cms-docker $ROOT_DIR
    else
        git clone https://github.com/Mourtz/cms-docker $ROOT_DIR/cms-docker
        if [ $? != 0 ];  then
            echo "coudn't clone cms-sw/cms-docker repo!"
            exit 1
        fi
    fi
else
    echo "$ROOT_DIR/cms-docker already exists"
fi

if [ $(sudo docker images -q cc7:latest) != 0 ]; then
    echo "CC7 Docker Image already exists!"
    echo "Skipping Docker build..."
else
    echo "Building Docker image..."

    sudo docker build -t cc7 $ROOT_DIR/cms-docker/cc7/
    if [ $? != 0 ]; then
        echo "couldn't build docker image!"
        exit 1
    fi
fi

# keep it
# sudo rm -rf $ROOT_DIR/cms-docker

#-------------------------------------------------------------

if [ $BOOTSTRAP == 0 ]; then
    _build=0
    if [ ! -d "$BUILD_DIR/cmsdist" ]; then
        let "_build++"
        git clone $CMS_DIST $BUILD_DIR/cmsdist
        if [ $? != 0 ];  then
            echo "coudn't clone cms-sw/cmsdist repo!"
            exit 1
        fi
    else
        echo "cms-sw/cmsdist already exists!"
    fi

    if [ ! -d "$BUILD_DIR/pkgtools" ]; then
        let "_build++"
        git clone https://github.com/cms-sw/pkgtools.git $BUILD_DIR/pkgtools
        if [ $? != 0 ];  then
            echo "coudn't clone cms-sw/pkgtools repo!"
            exit 1
        fi
    else
        echo "cms-sw/pkgtools already exists!"
    fi

    if [[ $FORCE_BUILD == 1 || $_build != 0 ]]; then
        echo "Building..."
        sudo docker run -i -t  \
        $DOCKER_VOLUMES \
        cc7 /bin/bash -c "./pkgtools/cmsBuild -a $SCRAM_ARCH -i ./data7 -j $(nproc --all) -c ./cmsdist build fwlite; ln -s ./data7/cmsset_default.sh ./"
    else
        echo "skipping build..."
    fi
else
    if [ ! -f "$BUILD_DIR/bootstrap.sh" ]; then
        wget http://cmsrep.cern.ch/cmssw/bootstrap.sh -O $BUILD_DIR/bootstrap.sh
        sudo chmod a+x $BUILD_DIR/bootstrap.sh
    fi

    if [ ! -d "$BUILD_DIR/bootstrap" ]; then
        echo "Bootstrapping..."

        sudo docker run -i -t  \
        $DOCKER_VOLUMES \
        cc7 /bin/bash -c "./bootstrap.sh -a $SCRAM_ARCH -r cms -path ./bootstrap setup; ln -s ./bootstrap/cmsset_default.sh ./"
    else
        echo "Skipping bootstrap..."
    fi
fi

#-------------------------------------------------------------

if [ $RUN_IMAGE == 1 ]; then
    echo "Starting Container..."

    export_enviroment

    if [ $BOOTSTRAP == 0 ]; then
        sudo docker run -p $DOCKER_PORT:$DOCKER_PORT -i -t  \
        $DOCKER_VOLUMES \
        cc7 /bin/bash --init-file env.sh
    else
        if [[ "$OSTYPE" == "linux-gnu" ]]; then
            xhost +"local:docker@"
        else
            echo "Didn' add hostname."
            echo "Check line: ${LINENO}"
        fi

        sudo docker run -i -t  \
        -e "DISPLAY=$DISPLAY" -v="/tmp/.X11-unix:/tmp/.X11-unix:rw" --privileged \
        $DOCKER_VOLUMES \
        cc7 /bin/bash --init-file env.sh
    fi
fi

#-------------------------------------------------------------

exit 0