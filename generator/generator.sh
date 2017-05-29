#!/bin/sh

tmpf=data && touch $tmpf

while true
do
  echo $RANDOM >> $tmpf
  sleep 2
done
