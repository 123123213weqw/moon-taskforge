# Request and result guide

Every example below is an executable fixture. Assertions cover the listed result fields; additional output fields are documented by the API and other fixtures. Error cases intentionally reject the request.

## initial ready wave

```json
{
  "tasks": [
    {
      "id": "a",
      "command": [
        "echo",
        "a"
      ],
      "inputs": [
        "in.txt"
      ],
      "outputs": [
        "a.txt"
      ]
    },
    {
      "id": "b",
      "deps": [
        "a"
      ],
      "command": [
        "echo",
        "b"
      ],
      "inputs": [
        "a.txt"
      ],
      "outputs": [
        "b.txt"
      ]
    }
  ],
  "hashes": {
    "in.txt": "h"
  }
}
```

Expected result fields:

```json
{
  "ready/0/id": "a",
  "tasks/1/status": "waiting",
  "terminal": false
}
```

## failure blocks downstream

```json
{
  "tasks": [
    {
      "id": "a",
      "command": [
        "echo",
        "a"
      ],
      "inputs": [
        "in.txt"
      ],
      "outputs": [
        "a.txt"
      ]
    },
    {
      "id": "b",
      "deps": [
        "a"
      ],
      "command": [
        "echo",
        "b"
      ],
      "inputs": [
        "a.txt"
      ],
      "outputs": [
        "b.txt"
      ]
    }
  ],
  "hashes": {
    "in.txt": "h"
  },
  "completed": {
    "a": "failed"
  }
}
```

Expected result fields:

```json
{
  "tasks/0/status": "failed",
  "tasks/1/status": "blocked",
  "terminal": true,
  "success": false
}
```

## missing input fails

```json
{
  "tasks": [
    {
      "id": "a",
      "command": [
        "echo",
        "a"
      ],
      "inputs": [
        "in.txt"
      ],
      "outputs": [
        "a.txt"
      ]
    },
    {
      "id": "b",
      "deps": [
        "a"
      ],
      "command": [
        "echo",
        "b"
      ],
      "inputs": [
        "a.txt"
      ],
      "outputs": [
        "b.txt"
      ]
    }
  ]
}
```

Expected result fields:

```json
{
  "tasks/0/status": "failed",
  "tasks/1/status": "blocked",
  "terminal": true
}
```

## topological cycle

```json
{
  "tasks": [
    {
      "id": "a",
      "deps": [
        "b"
      ],
      "command": [
        "x"
      ]
    },
    {
      "id": "b",
      "deps": [
        "a"
      ],
      "command": [
        "x"
      ]
    }
  ]
}
```

Expected: nonzero exit with an input error.

## output conflict

```json
{
  "tasks": [
    {
      "id": "a",
      "command": [
        "x"
      ],
      "outputs": [
        "same"
      ]
    },
    {
      "id": "b",
      "command": [
        "x"
      ],
      "outputs": [
        "same"
      ]
    }
  ]
}
```

Expected: nonzero exit with an input error.

## unsafe inputs

```json
{
  "tasks": [
    {
      "id": "a",
      "command": [
        "x"
      ],
      "inputs": [
        "../x"
      ]
    }
  ]
}
```

Expected: nonzero exit with an input error.

## producer dependency required

```json
{
  "tasks": [
    {
      "id": "a",
      "command": [
        "x"
      ],
      "outputs": [
        "a"
      ]
    },
    {
      "id": "b",
      "command": [
        "x"
      ],
      "inputs": [
        "a"
      ]
    }
  ]
}
```

Expected: nonzero exit with an input error.

## concurrency bound

```json
{
  "tasks": [
    {
      "id": "0",
      "command": [
        "x"
      ]
    },
    {
      "id": "1",
      "command": [
        "x"
      ]
    },
    {
      "id": "2",
      "command": [
        "x"
      ]
    },
    {
      "id": "3",
      "command": [
        "x"
      ]
    }
  ],
  "concurrency": 2
}
```

Expected result fields:

```json
{
  "tasks/2/status": "waiting",
  "ready/1/id": "1"
}
```

## Host adapter

```sh
node scripts/execute.mjs WORKFLOW.json WORKSPACE_DIR
```

Read the current boundaries before using this adapter.
