$16 macros [![NPM version][npm-image]][npm-url] [![Build Status][travis-image]][travis-url]
==========
**TL;DR:** JSON/CSON/YAML with ${variables}.
Everything's better with variables. And macros.

$16 macros is yet another template engine for Javascript. But unlike most other
template engines it expands any kinds of objects, not just strings.

While being designed to be used on top of YAML as a primary input format, the
engine itself is format-agnostic: it transforms generic Javascript objects, no
matter where they come from.

Installation and usage
----------------------
Install the
[sixteen-dollar-macros](https://www.npmjs.com/package/sixteen-dollar-macros)
package as a dependence:

```console
$ npm install sixteen-dollar-macros --save
```

Nothing special here:
```coffee
$16Macros = require 'sixteen-dollar-macros'
```

### API
```coffee
result = $16Macros.expand {hey: '$hi!'},
	variables:
	  hi: 'Hello World'
# {hey: 'Hello World!'}
```

[npm-url]: https://www.npmjs.com/package/sixteen-dollar-macros
[npm-image]: https://img.shields.io/npm/v/sixteen-dollar-macros.svg

[travis-url]: https://travis-ci.org/abusalimov/js-sixteen-dollar-macros
[travis-image]: https://travis-ci.org/abusalimov/js-sixteen-dollar-macros.svg?branch=master
