#!/bin/bash
# Script to Start/Stop TCPdump
# Usage: ./controltcpdump.sh start|stop [filename] [interface]
# Created by: Ha Son Hai (hasonhai124(at)gmail.com)

CONSOLEOUTPUT="tcpdump$( date +%m%d ).console"
HOSTNAME=`hostname -f`

usage() {
me=`basename $0`
echo '$me start|stop [filename] [interface]'
}

#Default filename:
if [ "$2" = "" ]; then
    FILENAME="dump_$HOSTNAME.dmp"
    ITF="any"
else
    FILENAME=$2
    if [ "$3" = "" ]; then
        ITF="any"
    else
        ITF=$3
    fi
fi

if [ "$1" = start ]; then
    echo $(date) $FILENAME >> $CONSOLEOUTPUT
    if [ "" = "$(pidof tcpdump)" ]; then
        tcpdump 'port 50070 or 50470 or 8020 or 9000 or 50075 or 50475 or 50010 or 50020 or 50090 or 10020 or 19888 or 13562 or 8088 or 8050 or 8025 or 8030 or 8141 or 45454 or 10200 or 8188 or 8190' -w $FILENAME -i $ITF > /dev/null &>> $CONSOLEOUTPUT &
        echo [$HOSTNAME] TCPdump is started\!
    else
        echo [$HOSTNAME] There is runnung process. Kill All\!
        killall -q tcpdump #Quiet, don't talk
        sleep 1
        if [ "" = "$(pidof tcpdump)" ]; then
            echo [$HOSTNAME] Restarting TCPdump...
            tcpdump 'port 50070 or 50470 or 8020 or 9000 or 50075 or 50475 or 50010 or 50020 or 50090 or 10020 or 19888 or 13562 or 8088 or 8050 or 8025 or 8030 or 8141 or 45454 or 10200 or 8188 or 8190' -w $FILENAME -i $ITF >/dev/null &>> $CONSOLEOUTPUT &
            echo [$HOSTNAME] TCPdump is started\!
        else
            echo [$HOSTNAME] Error\! Cannot kill them\!
            exit 0
        fi
    fi
else 
    if [ "$1" = stop ]; then
        TD=`pidof tcpdump`
        if [ -n "$TD" ]; then
            kill "$TD"
        fi
        sleep 1
        if [ "" = "$(pidof tcpdump)" ]; then
            echo [$HOSTNAME] TCPdump is stopped\!
        else
            echo [$HOSTNAME] Error\! Cannot kill them\!
            exit 0
        fi        
    else
        echo [$HOSTNAME] Syntax error\!
		usage
        exit 0
    fi
fi

