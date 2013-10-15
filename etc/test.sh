#!/bin/sh
CTL=$1

$CTL set_parameter stream-definition my_stream '{"local-username": "guest", "shards-per-node": 4}'
$CTL set_policy my_stream   "^stream\."   '{"stream-definition": "my_stream"}'
