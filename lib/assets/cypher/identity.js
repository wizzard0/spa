(function(){var t=function(t){var n,i,r,e;if(t instanceof ArrayBuffer){for(e=[],r=new Uint8Array(t),i=r.length,n=0;i>n;){e[n>>>2]|=(255&r[n])<<24-n%4*8,n++}return CryptoJS.lib.WordArray.create(e,i)}return t instanceof String||"string"==typeof t?CryptoJS.enc.Utf8.parse(t):void 0},n=function(t){return CryptoJS.enc.Utf8.stringify(t)};return function(i){return n(t(i))}})();