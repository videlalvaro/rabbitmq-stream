#!/bin/sh
CTL=$1

$CTL set_parameter stream-definition rkey '{"local-username": "guest", "shards-per-node": 2, "routing-key": "1234"}'
$CTL set_policy rkey-stream   "^rkey\."   '{"stream-definition": "rkey"}'
