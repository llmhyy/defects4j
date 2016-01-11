#!/usr/bin/env bash
#
################################################################################
# This script initializes Defects4J. In particular, it downloads and sets up:
# - the project's version control repositories
# - the Major mutation framework
# - the supported test generation tools
# - the supported code coverage tools (TODO)
################################################################################
# TODO: Major and the coverage tools should be moved to framework/lib

# Check whether wget is available
if ! wget --version > /dev/null 2>&1; then
    echo "Couldn't find wget to download dependencies. Please install wget and re-run this script."
    exit 1
fi

# Directories for project repositories and external libraries
BASE=$(cd $(dirname $0); pwd)
DIR_REPOS="$BASE/project_repos"
DIR_LIB_GEN="$BASE/framework/lib/test_generation/generation"
DIR_LIB_RT="$BASE/framework/lib/test_generation/runtime"
mkdir -p $DIR_LIB_GEN
mkdir -p $DIR_LIB_RT

#
# Download project repositories if necessary
#
cd $DIR_REPOS && ./get_repos.sh

#
# Download Major
#
MAJOR_VERSION="1.1.6"
MAJOR_URL="http://mutation-testing.org/downloads"
MAJOR_ZIP="major-${MAJOR_VERSION}_jre7.zip"
cd $BASE && wget -N $MAJOR_URL/$MAJOR_ZIP \
         && unzip $MAJOR_ZIP \
         && rm $MAJOR_ZIP

#
# Download EvoSuite
#
EVOSUITE_VERSION="0.2.0"
EVOSUITE_URL="http://www.evosuite.org/files"
EVOSUITE_JAR="evosuite-${EVOSUITE_VERSION}.jar"
EVOSUITE_RT_JAR="evosuite-standalone-runtime-${EVOSUITE_VERSION}.jar"
cd $DIR_LIB_GEN && wget -N $EVOSUITE_URL/$EVOSUITE_JAR \
                && ln -sf $EVOSUITE_JAR evosuite-current.jar 
cd $DIR_LIB_RT  && wget -N $EVOSUITE_URL/$EVOSUITE_RT_JAR \
                && ln -sf $EVOSUITE_RT_JAR evosuite-rt.jar 

#
# Download Randoop
#
RANDOOP_VERSION="2.0.1"
RANDOOP_URL="https://github.com/randoop/randoop/releases/download/v.${RANDOOP_VERSION}"
RANDOOP_JAR="randoop-${RANDOOP_VERSION}.jar"
cd $DIR_LIB_GEN && wget -N $RANDOOP_URL/$RANDOOP_JAR \
                && ln -sf $RANDOOP_JAR randoop-current.jar