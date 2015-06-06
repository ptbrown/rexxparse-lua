A Rexx-like String Parser

```lua
rexxparse = require "rexxparse.parse"
results = rexxparse.parse("test = 10", "name '=' value")
assert(results.test == '10')

parser = rexxparse.parse("name '=' value")
results = parser("test = 10")
parser(results, "test2 = 20")
```

