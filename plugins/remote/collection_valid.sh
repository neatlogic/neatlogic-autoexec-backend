#!/bin/bash
for file in `ls |grep collection_ |grep -v collection_valid`;do
   `perl -c $file`
done
