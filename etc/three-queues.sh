#!/bin/sh
CTL=$1

$CTL set_parameter stream-connection-params localhost '{"uri": "amqp://localhost"}'
$CTL set_parameter stream-definition 3_stream '{"connection-params": "localhost", "shards-per-node": 3}'
$CTL set_policy 3_stream   "^three\."   '{"stream-definition": "3_stream"}'
