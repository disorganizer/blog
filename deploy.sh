#!/bin/sh

rm public -rf
hugo
cp public /tmp/devlog -r
git checkout gh-pages
rm * -rf 
cp /tmp/devlog/* . -r
git add .
git commit -am "Update blog $date"
git push
git checkout master
