bindstops
=========

Daemon attaching to bind's query log, blocks clients exceeding query rates

Prereqs
-------

Needs Perl (reasonably recent) and the following (standard) Perl modules:
NDBM_File, Data::Dumper, Sys::Syslog, Date::Parse, POSIX
which should be included in a standard Perl installation

Tested/developed with bind 9.7.4-P1

Operation
---------

1. Opens the bind queries.log, reads it until EOF and waits for new entries, then reads those
2. Each entry is parsed and, if it's a query entry, a record is added to a query record list and
   a client record list
3. If a query record lists exceeds its rate for a defined window, that query is marked as blocked
   and all clients recorded for that query are blocked in iptables
4. If a client record lists exceeds its rate for a defined window, that client is blocked in iptables
5. If a record is added to a query record list which is marked as blocked, that client is blocked

So: Excessive client querying is blocked, excessive queries are blocked, clients querying blocked queries are blocked

Configuration
-------------

See CFG.pm

Control
-------

Start the program from it's directory.

Send signal SIGUSR1 to the process and it will dump out some statistics to syslog.
Send signal SIGHUP to the process and it will shutdown cleanly
