#!/bin/sh
CTL=$1

$CTL set_parameter stream-connection-params localhost '{"uri": "amqp://localhost"}'
$CTL set_parameter stream-definition my_stream '{"connection-params": "localhost", "shards-per-node": 4}'
$CTL set_policy my_stream   "^stream\."   '{"stream-definition": "my_stream"}'
