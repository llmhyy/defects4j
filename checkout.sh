#!/usr/bin/env bash
#This script is used to check out all the bug and fix version of the whole repository,

projects=(Chart Closure Lang Math Mockito Time)
bugNums=(26 133 65 106 38 27)

basePath=/mnt/linyun/bug_code

bid="b"
fid="f"
#projectName=""
#bugNum=""
#projectPath=""

for((i=0;i<6;i++)); do
	#echo ${projects[$i]}
	projectName=${projects[$i]}
	bugNum=${bugNums[$i]}
	projectPath="$basePath/$projectName"
	for((j=0;j<$bugNum;j++)); do
		v=$(($j+1))
		echo $v

		bugPath="$projectPath/$v"
		buggyPath="$bugPath/bug"
		fixPath="$bugPath/fix"

		echo $buggyPath

		mkdir -p $buggyPath
		mkdir -p $fixPath

		#echo "defects4j checkout -p $projectName -v $v$bid -w $buggyPath"

		defects4j checkout -p $projectName -v $v$bid -w $buggyPath
		cd $buggyPath
		defects4j test
		defects4j checkout -p $projectName -v $v$fid -w $fixPath
		cd $fixPath
		defects4j test
	done
	
done
