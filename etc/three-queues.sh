#!/bin/sh
CTL=$1

$CTL set_parameter stream-connection-params localhost '{"uri": "amqp://localhost"}'
$CTL set_parameter stream-definition 3_stream '{"connection-params": "localhost", "shards-per-node": 3}'
$CTL set_policy my-stream   "^three\."   '{"stream-definition": "3_stream"}'
