TESTER=perl -MTest::Harness
TFLAGS=-e '$$Test::Harness::verbose=1; runtests @ARGV;'

TESTFILES=*.t

.PHONY: tests clean

tests:
	$(TESTER) $(TFLAGS) $(TESTFILES)

clean:
	rm -fv *~
