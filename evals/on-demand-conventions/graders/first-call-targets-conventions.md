---
type: regex
target: trace
pattern: '^(?:(?!"type":"tool_use")[\s\S])*"type":"tool_use","id":"[^"]*","name":"[A-Za-z]+","input":\{(?:[^{}"]|"(?:[^"\\]|\\.)*")*"(?:[^"\\]|\\.)*conventions\.md'
weight: 2
---

The agent's first tool call names conventions.md.
