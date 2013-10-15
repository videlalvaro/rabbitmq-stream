#!/bin/sh
CTL=$1

$CTL set_parameter stream routing-key '"4321"'
$CTL set_parameter stream-definition rkey2 '{"local-username": "guest", "shards-per-node": 2}'
$CTL set_policy rkey2-stream   "^rkey2\."   '{"stream-definition": "rkey2"}'
