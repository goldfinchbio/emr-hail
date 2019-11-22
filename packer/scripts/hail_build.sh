#!/bin/bash
set -x -e
export PATH=$PATH:/usr/local/bin

HAIL_ARTIFACT_DIR="/opt/hail"
HAIL_PROFILE="/etc/profile.d/hail.sh"
JAR_HAIL="hail-all-spark.jar"
ZIP_HAIL="hail-python.zip"
REPOSITORY_URL="https://github.com/hail-is/hail.git"

function install_prereqs {
  mkdir -p "$HAIL_ARTIFACT_DIR"

  yum -y remove java-1.7.0-openjdk*

  yum -y update
  yum -y install \
  cmake \
  gcc72-c++ \
  git \
  java-1.8.0-openjdk \
  java-1.8.0-openjdk-devel \
  lz4 \
  lz4-devel \
  python36 \
  python36-devel \
  python36-setuptools

  # Upgrade latest latest pip
  python -m pip install --upgrade pip
  python3 -m pip install --upgrade pip

  WHEELS="argparse
  bokeh
  cycler
  decorator
  joblib
  jupyter
  kiwisolver
  llvmlite
  matplotlib
  numba
  numpy
  oauth
  pandas
  parsimonious
  pyserial
  requests
  scikit-learn
  scipy
  seaborn
  statsmodels
  umap-learn
  utils
  wheel"

  for WHEEL_NAME in $WHEELS
  do
    python3 -m pip install "$WHEEL_NAME"
  done

  python27 -m pip install ipykernel
}

function hail_build
{
  echo "Building Hail v.$HAIL_VERSION from source with Spark v.$SPARK_VERSION"

  git clone "$REPOSITORY_URL"
  cd hail/hail/
  git checkout "$HAIL_VERSION"

  JAVA_PATH=$(dirname "/usr/lib/jvm/java-1.8.0/include/.")
  if [ -z "$JAVA_PATH" ]; then
    echo "Java 8 was not found"
    exit 1
  else
    ln -s "$JAVA_PATH" /etc/alternatives/jre/include
  fi

  if [ "$HAIL_VERSION" != "master " ] && [[ "$HAIL_VERSION" < 0.2.18 ]]; then
    if [ "$SPARK_VERSION" = "2.2.0" ]; then
      ./gradlew -Dspark.version="$SPARK_VERSION" shadowJar archiveZip
    else
      ./gradlew -Dspark.version="$SPARK_VERSION" -Dbreeze.version=0.13.2 -Dpy4j.version=0.10.6 shadowJar archiveZip
    fi
  elif [ "$HAIL_VERSION" = "master" ] || [[ "$HAIL_VERSION" > 0.2.23 ]]; then
    make install-on-cluster HAIL_COMPILE_NATIVES=1 SPARK_VERSION="$SPARK_VERSION"
  else
    echo "Hail 0.2.19 - 0.2.23 builds are not possible due to incompatiable configurations resolved in 0.2.24."
    exit 1
  fi
}

function hail_install
{
  echo "Installing Hail locally"

  cat <<- HAIL_PROFILE > "$HAIL_PROFILE"
  export SPARK_HOME="/usr/lib/spark"
  export PYSPARK_PYTHON="python3"
  export PYSPARK_SUBMIT_ARGS="--conf spark.kryo.registrator=is.hail.kryo.HailKryoRegistrator --conf spark.serializer=org.apache.spark.serializer.KryoSerializer pyspark-shell"
  export PYTHONPATH="$HAIL_ARTIFACT_DIR/$ZIP_HAIL:\$SPARK_HOME/python:\$SPARK_HOME/python/lib/py4j-src.zip:\$PYTHONPATH"
HAIL_PROFILE

  if [[ "$HAIL_VERSION" < 0.2.24 ]]; then
    cp "$PWD/build/distributions/$ZIP_HAIL" "$HAIL_ARTIFACT_DIR"
  fi

  cp "$PWD/build/libs/$JAR_HAIL" "$HAIL_ARTIFACT_DIR"
}

function cleanup()
{
  rm -rf /root/.gradle
  rm -rf /home/ec2-user/hail
  rm -rf /root/hail
}

install_prereqs
hail_build
hail_install
cleanup
