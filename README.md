$16 macros [![NPM version][npm-image]][npm-url] [![Build Status][travis-image]][travis-url]
==========
**TL;DR:** JSON/CSON/YAML with ${variables}.
Everything's better with variables. And macros.

$16 macros is yet another template engine for Javascript. But unlike most other
template engines it expands any kinds of objects, not just strings.

While being designed to be used on top of YAML as a primary input format, the
engine itself is format-agnostic: it transforms generic Javascript objects, no
matter where they come from.

Features
--------
The mandatory "Hello World" example demonstrating basic usage of $variable
expansion:
<table>
<thead><tr><th>Input</th><th>Result</th></tr></thead>
<tbody><tr>
<td valign="top"><pre lang="yaml">
$%greeting: Hello World!

hey: $greeting
</pre></td>
<td valign="top"><pre lang="yaml">
hey: Hello World!
</pre></td>
</tr></tbody>
</table>

Here `$%greeting: ...` introduces a new variable named `greeting`, which is
expanded using a `$greeting` syntax afterwards. Multiple variables can be
defined using a single `$%:` block as an object mapping variable names to their
values.

Variables are **expanded recursively**, that is a variable can refer to another
variable:

<table>
<thead><tr><th>Input</th><th>Result</th></tr></thead>
<tbody><tr>
<td valign="top"><pre lang="yaml">
$%:
  greeting: $hello there!
  hello: Hi

hey: $greeting
</pre></td>
<td valign="top"><pre lang="yaml">
hey: Hi there!
</pre></td>
</tr></tbody>
</table>

The name of a variable to expand can be **computed dynamically**, that is other
variables may be referenced inside the name of the variable being expanded:

<table>
<thead><tr><th>Input</th><th>Result</th></tr></thead>
<tbody><tr>
<td valign="top"><pre lang="yaml">
$%:
  foo: bar
  bar: 42

answer: ${$foo}
</pre></td>
<td valign="top"><pre lang="yaml">
answer: 42
</pre></td>
</tr></tbody>
</table>

Variables can actually hold arbitrary objects of any types, not only strings or
other primitive types. Another nice feature is that you can access properties
within a variable reference using a dot after the variable name.

<table>
<thead><tr><th>Input</th><th>Result</th></tr></thead>
<tbody><tr>
<td valign="top"><pre lang="yaml">
$%:
  translations:
    en:
      greetings: [Hi, Hello]
    ru:
      greetings: [Привет, Салют]
  strings: ${translations.$lang}

$%lang: en

greet: ${strings.greetings.1}!
</pre></td>
<td valign="top"><pre lang="yaml">
greet: Hello!
</pre></td>
</tr></tbody>
</table>

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
result = $16Macros.expand {hey: '$hi!'}, hi: 'Hello World'
# {hey: 'Hello World!'}
```

[npm-url]: https://www.npmjs.com/package/sixteen-dollar-macros
[npm-image]: https://img.shields.io/npm/v/sixteen-dollar-macros.svg

[travis-url]: https://travis-ci.org/abusalimov/js-sixteen-dollar-macros
[travis-image]: https://travis-ci.org/abusalimov/js-sixteen-dollar-macros.svg?branch=master
