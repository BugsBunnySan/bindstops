EDITOR=emacs 

TESTER=perl -MTest::Harness
TFLAGS=-e '$$Test::Harness::verbose=1; runtests @ARGV;'

MAIN=bindstats.pl
MODULES=BS.pm IPT.pm WRL.pm
TESTFILES=*.t

.PHONY: tests clean edit edit_all

tests:
	$(TESTER) $(TFLAGS) $(TESTFILES)

clean:
	rm -fv *~

edit:
	$(EDITOR) $(MODULES) $(MAIN)

edit_all:
	$(EDITOR) Makefile $(TESTFILES) $(MODULES) $(MAIN)
