#!/bin/bash
# To plot the figure, but this code cannot run on the hadoop server because it does not have X-Windows
gnuplot -p <<%
set term wxt background "gray"
set mxtics 5
set mytics 5
set xrange [0:600]
set yrange [0:5]
set grid xtics ytics mxtics mytics
plot "am.delays",  "datanode.delays",  "map.delays",  "namenode.delays",  "nodemanager.delays",  "reduce.delays",  "yarn.delays"
%
