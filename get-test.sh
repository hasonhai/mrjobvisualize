#!/bin/bash

id="$1"
jobid="job_$1"
applicationid="application_$1"

echo Combine all logs to one file per service
echo Combine yarn logs
gawk -v svr="$YARNRM" '{ print $0,svr}' $DATAOUT/yarn_$YARNRM.log > $DATAOUT/combined_yarn.log
YARNRMLOGFILE="$DATAOUT/combined_yarn.log"
echo Combine namenode logs
gawk -v svr="$HADOOPNN" '{ print $0,svr}' $DATAOUT/namenode_$HADOOPNN.log > $DATAOUT/combined_namenode.log
HADOOPNNLOGFILE="$DATAOUT/combined_namenode.log"

echo Combine datanode logs
for server in `cat $CLUSTER`; do
    if [ -f $DATAOUT/datanode_$server.log  ]; then
        gawk -v svr="$server" '{ print $0,svr}' $DATAOUT/datanode_$server.log >> $DATAOUT/combined_datanode.log
    fi
done
HADOOPDNLOGFILE="$DATAOUT/combined_datanode.log"

echo Combine nodemanager logs
for server in `cat $CLUSTER`; do
    if [ -f $DATAOUT/datanode_$server.log  ]; then
        gawk -v svr="$server" '{ print $0,svr}' $DATAOUT/nodemanager_$server.log >> $DATAOUT/combined_nodemanager.log
    fi
done
YARNNMLOGFILE="$DATAOUT/combined_nodemanager.log"

if [ "$PACKAGE_COLLECT" = "TRUE" ]; then
    for server in `cat $CLUSTER`; do
        # Before combining log, should separate between packet send and packet received
        gawk -v svr="$server" '{ print $0,svr}' $DATAOUT/dump_$server.log >> $DATAOUT/combined_pcap.log
    done
    PCAPLOG="$DATAOUT/combined_pcap.log"
fi

echo Parsing containers\' logs...
while read containerinfo; do
    containername=`echo $containerinfo | gawk '{ print $1 }'`
    containerid=`echo $containername | gawk -F "_" '{ print $6 }'`
    server=`echo $containerinfo | gawk '{ print $4 }'`
    if [ "$containerid" = "000001" ]; then
        echo Container $containername is Application Master
        gawk -v svr="$server" '{ print $0,svr}' $DATAOUT/${containername}_${server}.syslog > $DATAOUT/am.syslog
    else
        mapper_test=`grep -m 1 -c -e "Task 'attempt_${id}_m_[0-9]*_[0-9]*' done" $DATAOUT/${containername}_${server}.syslog`
        reducer_test=`grep -m 1 -c -e "Task 'attempt_${id}_r_[0-9]*_[0-9]*' done" $DATAOUT/${containername}_${server}.syslog`
        if [ "$mapper_test" = "1" ]; then
            echo "Container $containername is mapper -> append mapper logs to map.syslog"
            gawk -v svr="$server" '{ print $0,svr}' $DATAOUT/${containername}_${server}.syslog >> $DATAOUT/map.syslog
        elif [ "$reducer_test" = "1" ]; then
            echo "Container $containername is reducer -> append reducer logs to reduce.syslog"
            gawk -v svr="$server" '{ print $0,svr}' $DATAOUT/${containername}_${server}.syslog >> $DATAOUT/reduce.syslog
        else echo "Container $containername is not recognizable"
        fi
        #TODO: Distinguised between mapper to see if the job is running in parallel.
    fi
done < $DATAOUT/containers

echo Finding start time and end time from YARN logs file
export startline=`grep -n -s "Storing application with id $applicationid" $YARNRMLOGFILE | gawk -F ":" '{print $1}'`
export startdate=`gawk 'NR=='$startline-2' {print $0}' $YARNRMLOGFILE | gawk '{print $1}'`
export starttime=`gawk 'NR=='$startline-2' {print $0}' $YARNRMLOGFILE | gawk '{print $2}'`
echo "starttime"=$startdate $starttime
# old version
# export enddate=`grep -m 1 "Application removed - appId: $applicationid" $YARNRMLOGFILE | gawk '{print $1}'`
# export endtime=`grep -m 1 "Application removed - appId: $applicationid" $YARNRMLOGFILE | gawk '{print $2}'`
# new version
export enddate=`grep -m 1 "$applicationid unregistered successfully." $YARNRMLOGFILE | gawk '{print $1}'`
export endtime=`grep -m 1 "$applicationid unregistered successfully." $YARNRMLOGFILE | gawk '{print $2}'`
echo "endtime="$enddate $endtime

echo Filter only log records related to job $applicationid...
if [ "$PACKAGE_COLLECT" = "TRUE" ] ; then
gawk -v startd=$startdate -v startt=$starttime -v endd=$enddate -v endt=$endtime ' BEGIN {start=startd " " startt;end=endd " " endt}  $1 ~ startd {if ($1 " " $2 >= start) {if ($1 " " $2 <= end) print $0;}} ' $PCAPLOG > $DATAOUT/pcap.syslog
fi
gawk -v startd=$startdate -v startt=$starttime -v endd=$enddate -v endt=$endtime ' BEGIN {start=startd " " startt;end=endd " " endt}  $1 ~ startd {if ($1 " " $2 >= start) {if ($1 " " $2 <= end) print $0;}} ' $YARNRMLOGFILE > $DATAOUT/yarn.syslog
gawk -v startd=$startdate -v startt=$starttime -v endd=$enddate -v endt=$endtime ' BEGIN {start=startd " " startt;end=endd " " endt}  $1 ~ startd {if ($1 " " $2 >= start) {if ($1 " " $2 <= end) print $0;}} ' $YARNNMLOGFILE > $DATAOUT/nodemanager.syslog
gawk -v startd=$startdate -v startt=$starttime -v endd=$enddate -v endt=$endtime ' BEGIN {start=startd " " startt;end=endd " " endt}  $1 ~ startd {if ($1 " " $2 >= start) {if ($1 " " $2 <= end) print $0;}} ' $HADOOPNNLOGFILE > $DATAOUT/namenode.syslog
gawk -v startd=$startdate -v startt=$starttime -v endd=$enddate -v endt=$endtime ' BEGIN {start=startd " " startt;end=endd " " endt}  $1 ~ startd {if ($1 " " $2 >= start) {if ($1 " " $2 <= end) print $0;}} ' $HADOOPDNLOGFILE > $DATAOUT/datanode.syslog

# Add event mark at the beginning of line
if [ "$PACKAGE_COLLECT" = "TRUE" ] ; then
    gawk '{$1="PCAP     ";print $0}' $DATAOUT/pcap.syslog > $DATAOUT/PCAP.out
fi
gawk '{$1="AM       ";print $0}' $DATAOUT/am.syslog > $DATAOUT/AM.out
gawk '{$1="REDUCE   ";print $0}' $DATAOUT/reduce.syslog > $DATAOUT/REDUCE.out
gawk '{$1="MAP      ";print $0}' $DATAOUT/map.syslog > $DATAOUT/MAP.out
gawk '{$1="YARN     ";print $0}' $DATAOUT/yarn.syslog > $DATAOUT/YARN.out
gawk '{$1="DATAN    ";print $0}' $DATAOUT/datanode.syslog > $DATAOUT/DATAN.out
gawk '{$1="NAMEN    ";print $0}' $DATAOUT/namenode.syslog > $DATAOUT/NAMEN.out
gawk '{$1="NODEM    ";print $0}' $DATAOUT/nodemanager.syslog > $DATAOUT/NODEM.out

echo "Combine all logs from diffrent service to one Job Logs File"
sort -k 2,2 $DATAOUT/AM.out  $DATAOUT/MAP.out  $DATAOUT/REDUCE.out  $DATAOUT/YARN.out $DATAOUT/DATAN.out $DATAOUT/NAMEN.out $DATAOUT/NODEM.out > $DATAOUT/jobsorted
cp $DATAOUT/jobsorted $DATAOUT/JobAllLogs.txt
if [ "$PACKAGE_COLLECT" = "TRUE" ] ; then sort -k 2,2 $DATAOUT/PCAP.out > $DATAOUT/pcapsorted; fi
echo "Genereate .delays file for drawing Job Visual Map" 
# generate timing of MR jobs for gnuplot: Jobsumm obtained from syslogs under hadoop/logs for job
export T00=$(echo $starttime | sed 's/,/./' | gawk -F: -vOFMT=%.6f '{ print ($2 * 60) + $3 }')
echo $T00
# We should convert starttime and logs time to second, then shift the log time to the beginning of the figure.

sed 's/,/./' $DATAOUT/jobsorted |  gawk '{print $0, $1}' | gawk -F ":" -vOFMT=%.6f '!(t>0) {t=($2 * 60) + $3} {nt=($2 * 60) + $3-'$T00'; if (nt > 0) print nt ,$0}' > $DATAOUT/jobtmp1.delays
# This line to map the server name to a number to present it on the y-axis of the figure
gawk '{print $1,$(NF-1),$0}' $DATAOUT/jobtmp1.delays > $DATAOUT/jobtmp.delays
rm $DATAOUT/jobtmp1.delays
cat $MAPFILE | while read line; do
neww=${line##* }
oldw=${line%% *}
sed -i "s/$oldw/$neww/" $DATAOUT/jobtmp.delays
done 

if [ "$PACKAGE_COLLECT" = "TRUE" ] ; then
    sed 's/,/./' $DATAOUT/pcapsorted |  gawk '{print $0, $1}' | gawk -F ":" -vOFMT=%.6f '!(t>0) {t=($2 * 60) + $3} {nt=($2 * 60) + $3-'$T00'; if (nt > 0) print nt ,$0}' > $DATAOUT/pcaptmp1.delays
    # This line to map the server name to a number to present it on the y-axis of the figure
    gawk '{print $1,$(NF-1),$0}' $DATAOUT/pcaptmp1.delays > $DATAOUT/pcaptmp.delays
    rm $DATAOUT/pcaptmp1.delays
    cat $MAPFILE | while read line; do
    neww=${line##* }
    oldw=${line%% *}
    sed -i "s/$oldw/$neww.1/" $DATAOUT/pcaptmp.delays
    done
fi
  
grep "YARN$" $DATAOUT/jobtmp.delays > $DATAOUT/yarn.delays
grep "AM$" $DATAOUT/jobtmp.delays > $DATAOUT/am.delays
grep "MAP$" $DATAOUT/jobtmp.delays > $DATAOUT/map.delays
grep "REDUCE$" $DATAOUT/jobtmp.delays > $DATAOUT/reduce.delays
grep "DATAN$" $DATAOUT/jobtmp.delays > $DATAOUT/datanode.delays
grep "NAMEN$" $DATAOUT/jobtmp.delays > $DATAOUT/namenode.delays
grep "NODEM$" $DATAOUT/jobtmp.delays > $DATAOUT/nodemanager.delays
if [ "$PACKAGE_COLLECT" = "TRUE" ] ; then  
    grep "PCAP$" $DATAOUT/pcaptmp.delays | grep -v "length 0" > $DATAOUT/pcap.delays # remove packet of length 0
    rm $DATAOUT/pcaptmp.delays
fi
rm $DATAOUT/jobtmp.delays
echo Done
#plot-test
