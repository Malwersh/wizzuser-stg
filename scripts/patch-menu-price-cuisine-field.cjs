'use strict';
// Compatibility patch for the existing deployed menu-price bundle. Does not
// replace other deployed modules or change the pricing/rounding policy.
const fs=require('node:fs');
const file=process.argv[2];if(!file)throw Error('Bundle path required');
const source=fs.readFileSync(file,'utf8');
const old='      "reviewCount",\n      "publishedCategory"\n    ];';
const next='      "reviewCount",\n      "publishedCategory",\n      "cuisineIds"\n    ];';
if(source.includes(next))process.exit(0);
if(source.split(old).length!==2)throw Error('Unexpected bundle: inspect before patching');
fs.writeFileSync(file,source.replace(old,next));
