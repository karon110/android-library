#!/bin/sh

#1: GIT_USERNAME
#2: GIT_TOKEN
#3: BRANCH
#4: LOG_USERNAME
#5: LOG_PASSWORD
#6: DRONE_BUILD_NUMBER
#7: PULL_REQUEST_NUMBER

ruby scripts/analysis/lint-up.rb $1 $2 $3
lintValue=$?

# exit codes:
# 0: count was reduced
# 1: count was increased
# 2: count stayed the same

./gradlew findbugs

echo "Branch: $3"

if [ $3 = "master" ]; then
    echo "New findbugs result for master at: https://www.kaminsky.me/nc-dev/library-findbugs/master.html"
    curl -u $4:$5 -X PUT https://nextcloud.kaminsky.me/remote.php/webdav/library-findbugs/master.html --upload-file build/reports/findbugs/findbugs.html
    
    summary=$(sed -n "/<h1>Summary<\/h1>/,/<h1>Warnings<\/h1>/p" build/reports/findbugs/findbugs.html | head -n-1 | sed s'/<\/a>//'g | sed s'/<a.*>//'g | sed s'/Summary/FindBugs (master)/' | tr "\"" "\'" | tr -d "\r\n")
    curl -u $4:$5 -X PUT -d "$summary" https://nextcloud.kaminsky.me/remote.php/webdav/library-findbugs/findbugs.html
    
    if [ $lintValue -ne 1 ]; then
        echo "New lint result for master at: https://www.kaminsky.me/nc-dev/library-lint/master.html"
        curl -u $4:$5 -X PUT https://nextcloud.kaminsky.me/remote.php/webdav/library-lint/master.html --upload-file build/reports/lint/lint.html
        exit 0
    fi
else
    if [ -e $6 ]; then
        6="master-"$(date +%F)
    fi
    echo "New lint results at https://www.kaminsky.me/nc-dev/library-lint/$6.html"
    curl 2>/dev/null -u $4:$5 -X PUT https://nextcloud.kaminsky.me/remote.php/webdav/library-lint/$6.html --upload-file build/reports/lint/lint.html
    
    echo "New findbugs results at https://www.kaminsky.me/nc-dev/library-findbugs/$6.html"
    curl 2>/dev/null -u $4:$5 -X PUT https://nextcloud.kaminsky.me/remote.php/webdav/library-findbugs/$6.html --upload-file build/reports/findbugs/findbugs.html
    
    # delete all old comments
    oldComments=$(curl 2>/dev/null -u $1:$2 -X GET https://api.github.com/repos/nextcloud/android-library/issues/$7/comments | jq '.[] | (.id |tostring)  + "|" + (.user.login | test("nextcloud-android-bot") | tostring) ' | grep true | tr -d "\"" | cut -f1 -d"|")
    
    echo $oldComments | while read comment ; do 
        curl 2>/dev/null -u $1:$2 -X DELETE https://api.github.com/repos/nextcloud/android-library/issues/comments/$comment
    done
    
    # lint and findbugs file must exist
    if [ ! -s build/reports/lint/lint.html ] ; then
        echo "lint.html file is missing!"
        exit 1
    fi
    
    if [ ! -s build/reports/findbugs/findbugs.html ] ; then
        echo "findbugs.html file is missing!"
        exit 1
    fi 
    
    # add comment with results
    lintResultNew=$(grep "Lint Report.* [0-9]* warnings" build/reports/lint/lint.html | cut -f2 -d':' |cut -f1 -d'<')
    
    lintErrorNew=$(echo $lintResultNew | grep  "[0-9]* error" -o | cut -f1 -d" ")
    if ( [ -z $lintErrorNew ] ); then
        lintErrorNew=0
    fi
    
    lintWarningNew=$(echo $lintResultNew | grep  "[0-9]* warning" -o | cut -f1 -d" ")
    if ( [ -z $lintWarningNew ] ); then
        lintWarningNew=0
    fi
    
    lintErrorOld=$(grep "[0-9]* error" scripts/analysis/lint-results.txt -o | cut -f1 -d" ")
    if ( [ -z $lintErrorOld ] ); then
        lintErrorOld=0
    fi
    
    lintWarningOld=$(grep "[0-9]* warning" scripts/analysis/lint-results.txt -o | cut -f1 -d" ")
    if ( [ -z $lintWarningOld ] ); then
        lintWarningOld=0
    fi
    
    lintResult="<h1>Lint</h1><table width='500' cellpadding='5' cellspacing='2'><tr class='tablerow0'><td>Type</td><td><a href='https://www.kaminsky.me/nc-dev/library-lint/master.html'>Master</a></td><td><a href='https://www.kaminsky.me/nc-dev/library-lint/"$6".html'>PR</a></td></tr><tr class='tablerow1'><td>Warnings</td><td>"$lintWarningOld"</td><td>"$lintWarningNew"</td></tr><tr class='tablerow0'><td>Errors</td><td>"$lintErrorOld"</td><td>"$lintErrorNew"</td></tr></table>"
    findbugsResultNew=$(sed -n "/<h1>Summary<\/h1>/,/<h1>Warnings<\/h1>/p" build/reports/findbugs/findbugs.html |head -n-1 | sed s'/<\/a>//'g | sed s'/<a.*>//'g | sed s"#Summary#<a href=\"https://www.kaminsky.me/nc-dev/library-findbugs/$6.html\">FindBugs</a> (new)#" | tr "\"" "\'" | tr -d "\n")
    findbugsResultOld=$(curl 2>/dev/null https://nextcloud.kaminsky.me/index.php/s/9BjSFLsWY988ZKR/download | tr "\"" "\'" | tr -d "\r\n" | sed s'#FindBugs#<a href=\"https://www.kaminsky.me/nc-dev/library-findbugs/master.html">FindBugs</a>#'| tr "\"" "\'" | tr -d "\n") 
    curl -u $1:$2 -X POST https://api.github.com/repos/nextcloud/android-library/issues/$7/comments -d "{ \"body\" : \"$lintResult $findbugsResultNew $findbugsResultOld \" }"

    if [ $lintValue -eq 2 ]; then
        exit 0
    else
        exit $lintValue
    fi  
fi