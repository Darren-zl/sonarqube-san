#!/bin/bash

echo "begin ...."

SONAR_USER=admin SONAR_PASSWORD=password INFLUX_USER=root INFLUX_PASSWORD=password INFLUX_DB=sonarqube_data INTERVAL=‭43200‬ python sonar-client.py

echo "end!!!"
