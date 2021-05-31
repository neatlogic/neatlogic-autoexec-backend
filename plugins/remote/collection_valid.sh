#!/bin/bash
for file in `ls |grep collection_ |grep -v collection_valid`;do
   perl -c $file/$file;
   perltidy -i=4 -ci=4 -l=200 -b $file/$file;
   rm -f "${file}/$file.bak";
done
