# Third-party notices

Lightspot's Mac Tweaks ports logic from [RemoveMacAI](https://github.com/omlahore/RemoveMacAI) by
omlahore: Free Up Space (what it offers, how it sizes it, which caches are macOS's own, and how it
moves what only an administrator can move in one batch), Apple Intelligence (the feature and
model-set catalog, the feature-state reading, the configuration profile and its download block, and
the asset-service calls), Settings (the tweak catalog, reading and writing preferences, the undo
journal, the plan, and Music's launch entry) and Background Items (which launch agents and daemons
it lists, how it tells an updater and a leftover, and turning them off and on). RemoveMacAI's code
is not included as such; it was read and rewritten for Lightspot. RemoveMacAI is distributed under the MIT License:

```
MIT License

Copyright (c) 2026 omlahore

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

RemoveMacAI's Apple Intelligence work, which Mac Tweaks ports, builds on
[pared](https://github.com/4evy/pared) by 4evy. pared mapped the Unified Asset Framework reset
operation, the model asset sets and several of the settings keys for macOS 27. Lightspot's
asset-service bridge (`Core/AppleAssetService.swift`), its model catalog and its download block
follow that work. pared is distributed under the MIT License:

```
MIT License

Copyright (c) 2026 4evy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
