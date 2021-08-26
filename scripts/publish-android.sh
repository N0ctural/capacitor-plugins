#!/usr/bin/env bash

publish_plugin () {
    PLUGIN_PATH=$1
    if [ -d "$PLUGIN_PATH" ]; then
        # Android dir path
        ANDROID_PATH=$PLUGIN_PATH/android
        GRADLE_FILE=$ANDROID_PATH/build.gradle

        # Only try to publish if the directory contains a package.json and android package
        if test -f "$PLUGIN_PATH/package.json" && test -d "$ANDROID_PATH" && test -f "$GRADLE_FILE"; then
            PLUGIN_VERSION=$(grep '"version": ' "$PLUGIN_PATH"/package.json | awk '{print $2}' | tr -d '",')
            PLUGIN_NAME=$(grep '"name": ' "$PLUGIN_PATH"/package.json | awk '{print $2}' | tr -d '",')
            PLUGIN_NAME=${PLUGIN_NAME#@capacitor/}
            LOG_OUTPUT=./tmp/$PLUGIN_NAME.txt

            # Get latest plugin info from MavenCentral
            PLUGIN_PUBLISHED_URL="https://repo1.maven.org/maven2/com/capacitorjs/$PLUGIN_NAME/maven-metadata.xml"
            PLUGIN_PUBLISHED_DATA=$(curl -s $PLUGIN_PUBLISHED_URL)
            PLUGIN_PUBLISHED_VERSION="$(perl -ne 'print and last if s/.*<latest>(.*)<\/latest>.*/\1/;' <<< $PLUGIN_PUBLISHED_DATA)"

            if [[ $PLUGIN_VERSION == $PLUGIN_PUBLISHED_VERSION ]]; then
                printf %"s\n\n" "Duplicate: a published plugin $PLUGIN_NAME exists for version $PLUGIN_VERSION, skipping..."
            else
                # Make log dir if doesnt exist
                mkdir -p ./tmp

                printf %"s\n" "Attempting to build and publish plugin $PLUGIN_NAME for version $PLUGIN_VERSION"

                # Export ENV variables used by Gradle for the plugin
                export PLUGIN_NAME
                export PLUGIN_VERSION

                # Temporarily insert the latest Capacitor Core dependency version for publishing
                perl -i -pe"s/%%CAPACITOR_VERSION%%/$CAPACITOR_VERSION/g" $GRADLE_FILE

                # Build and publish
                "$ANDROID_PATH"/gradlew clean build publishReleasePublicationToSonatypeRepository --max-workers 1 -b "$ANDROID_PATH"/build.gradle -Pandroid.useAndroidX=true -Pandroid.enableJetifier=true > $LOG_OUTPUT 2>&1

                # Replace %%CAPACITOR_VERSION%% back so we dont commit a real capacitor version to the publish branch
                perl -i -pe"s/rootProject.ext.capacitorVersion : '$CAPACITOR_VERSION'/rootProject.ext.capacitorVersion : '%%CAPACITOR_VERSION%%'/g" $GRADLE_FILE

                if grep --quiet "BUILD SUCCESSFUL" $LOG_OUTPUT; then
                    printf %"s\n\n" "Success: $PLUGIN_NAME published to MavenCentral Staging. Manually review and release from the Sonatype Repository Manager https://s01.oss.sonatype.org/"
                else
                    printf %"s\n\n" "Error publishing $PLUGIN_NAME, check $LOG_OUTPUT for more info!"
                    cat $LOG_OUTPUT
                    exit 1
                fi
            fi
        else
            printf %"s\n\n" "$PLUGIN_PATH does not appear to be a plugin (has no package.json file or Android package), skipping..."
        fi
    fi
}

# Plugins base location
DIR=..

# Get the latest version of Capacitor
CAPACITOR_PACKAGE_JSON="https://raw.githubusercontent.com/ionic-team/capacitor/main/android/package.json"
CAPACITOR_VERSION=$(curl -s $CAPACITOR_PACKAGE_JSON | awk -F\" '/"version":/ {print $4}')

# Don't continue if there was a problem getting the latest version of Capacitor
if [[ $CAPACITOR_VERSION ]]; then
    printf %"s\n\n" "Attempting to publish new plugins with dependency on Capacitor Version $CAPACITOR_VERSION"
else
    printf %"s\n\n" "Error resolving latest Capacitor version from $CAPACITOR_PACKAGE_JSON"
    exit 1
fi

# Get latest com.capacitorjs:core XML version info
CAPACITOR_PUBLISHED_URL="https://repo1.maven.org/maven2/com/capacitorjs/core/maven-metadata.xml"
CAPACITOR_PUBLISHED_DATA=$(curl -s $CAPACITOR_PUBLISHED_URL)
CAPACITOR_PUBLISHED_VERSION="$(perl -ne 'print and last if s/.*<latest>(.*)<\/latest>.*/\1/;' <<< $CAPACITOR_PUBLISHED_DATA)"

# Check if we need to publish a new native version of the Capacitor Android library
if [[ "$CAPACITOR_VERSION" != "$CAPACITOR_PUBLISHED_VERSION" ]]; then
    printf %"s\n" "Publish Capacitor Core first! The latest published Android library version $CAPACITOR_PUBLISHED_VERSION in MavenCentral is outdated. There is an unpublished version $CAPACITOR_VERSION in ionic-team/capacitor."
    exit 1
else
    # Capacitor version in MavenCentral is up to date, continue publishing the native Capacitor Plugins
    printf %"s\n\n" "Latest native Capacitor Android library is version $CAPACITOR_PUBLISHED_VERSION and is up to date, continuing with plugin publishing..."

    # If run without args, process all plugins, else run over the plugins provided as args
    if [ "$#" -eq  "0" ]
    then
        # Run publish task for all plugins
        for f in "$DIR"/*; do
            publish_plugin $f
        done
    else
        # Run publish task for plugins provided as arguments
        for var in "$@"; do
            PLUGIN_DIR="$DIR"/$var
            publish_plugin $PLUGIN_DIR
        done
    fi
fi