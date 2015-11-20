PHONY: *

build:
	npm install .

check:
	jsstyle -o indent=4,unparenthesized-return=0,blank-after-open-comment=0 raft-test.js
	jsl --verbose --nologo --nofilelisting --conf=lint.conf raft-test.js

test:
	node ./raft-test.js
