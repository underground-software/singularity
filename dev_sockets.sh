#!/bin/sh
set -eu
ONE=''
[ '0' -eq "$(id -u)" ] || ONE='1'
socat TCP-LISTEN:"$ONE"443,fork,reuseaddr UNIX-CONNECT:./socks/https.sock &
socat TCP-LISTEN:"$ONE"465,fork,reuseaddr UNIX-CONNECT:./socks/smtps.sock &
socat TCP-LISTEN:"$ONE"995,fork,reuseaddr UNIX-CONNECT:./socks/pop3s.sock
