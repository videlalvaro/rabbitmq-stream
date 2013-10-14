#!/bin/sh
CTL=$1

$CTL set_parameter stream-connection-params localhost '{"uri": "amqp://localhost", "routing-key": "1234"}'
$CTL set_parameter stream-definition rkey '{"connection-params": "localhost", "shards-per-node": 2}'
$CTL set_policy rkey-stream   "^rkey\."   '{"stream-definition": "rkey"}'
