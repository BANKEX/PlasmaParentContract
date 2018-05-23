const ethUtil = require('ethereumjs-util')
const assert = require('assert');

exports.defineProperties = function (self, fields, data) {
    self._raw = []
    self._fields = []
    self._classes = []
    self._isArray = []
  
    /**
     * Computes a sha3-256 hash of the serialized object
     * @return {Buffer}
     */
    self.hash = function () { 
        var rlpEncoded = self.rlpEncode();
        return ethUtil.hashPersonalMessage(rlpEncoded);
      }


    // attach the `toJSON`
    self.toJSON = function (label) {
      if (label) {
        var obj = {}
        self._fields.forEach(function (field) {
          if (!self[field] || typeof self[field] === "undefined"){
            return;
          }
          if (self[field].constructor.name === "Buffer") {
            obj[field] = '0x' + self[field].toString('hex');
            return;
          } else if (self[field].toJSON != undefined) {
            obj[field] = '0x' + self[field].toJSON(label);
            return;
          }
        })
        return obj
      }
      return ethUtil.baToJSON(self._raw)
    }
  
    self.serialize = function serialize () {
        return self.rlpEncode();
    //   return Buffer.concat(this.raw)
    }

    self.rlpEncode = function rlpEncode() {
        return ethUtil.rlp.encode(self.raw)
    }
  
    Object.defineProperty(self, 'raw', {
        enumerable: true,
        configurable: false,
        get: function() {
            var toReturn = [];
            self._raw.forEach(function (rawItem, i) {
                if (self._raw[i].constructor.name === "Buffer") {
                    toReturn.push(self._raw[i]);
                } else if (self._raw[i].constructor.name === "Array") {
                    var items = [];
                    self._raw[i].forEach(function(subitem, j) {
                      if (subitem.raw !== undefined) {
                        items.push(subitem.raw)
                      } else {
                        items.push(subitem)
                      }
                        // if (subitem.rlpEncode !== undefined) {
                        //     items.push(subitem.rlpEncode())
                        // } else {
                        //     items.push(ethUtil.rlp.encode(subitem.raw))
                        // }
                    });
                    toReturn.push(items);
                    // toReturn.push(ethUtil.rlp.encode(items));
                } else if (self._raw[i].raw !== undefined) {
                    toReturn.push(self._raw[i].raw)
                } else {
                  throw Error("Error")
                }
            });
            return toReturn;
        }
    });


    fields.forEach(function (field, i) {
      self._fields.push(field.name);
      self._classes.push(field.class);
      var isArray = field.array ? true: false;
      self._isArray.push(isArray);
      var envelope = field.envelope ? true : false; 
      function getter () {
          return self._raw[i];
      }
      function setter (v) {
          if (envelope) {
              if (isArray) {
                assert(v.constructor.name === "Array", 'The field ' + field.name + ' must be an array')
              }
              self._raw[i] = v
              return;
          }

        v = ethUtil.toBuffer(v)
  
        if (v.toString('hex') === '00' && !field.allowZero) {
          v = Buffer.allocUnsafe(0)
        }
  
        if (field.allowLess && field.length) {
          v = ethUtil.stripZeros(v)
          assert(field.length >= v.length, 'The field ' + field.name + ' must not have more ' + field.length + ' bytes')
        } else if (!(field.allowZero && v.length === 0) && field.length) {
          assert(field.length === v.length, 'The field ' + field.name + ' must have byte length of ' + field.length)
        }

        self._raw[i] = v
      }
  
      Object.defineProperty(self, field.name, {
        enumerable: true,
        configurable: true,
        get: getter,
        set: setter
      })
  
      if (field.default) {
        self[field.name] = field.default
      }
  
      // attach alias
      if (field.alias) {
        Object.defineProperty(self, field.alias, {
          enumerable: false,
          configurable: true,
          set: setter,
          get: getter
        })
      }

      
    })
  
    // if the constuctor is passed data
    if (data) {
      if (typeof data === 'string' || data.constructor.name === "Buffer") {
        data = ethUtil.rlp.decode(data);
        // data = Buffer.from(ethUtil.stripHexPrefix(data), 'hex')
      }
 
      if (Array.isArray(data)) {
        if (data.length > self._fields.length) {
          throw (new Error('wrong number of fields in data'))
        }
  
        // make sure all the items are buffers
        data.forEach(function (d, i) {
            if (typeof self._classes[i] !== "undefined") {
                if (self._isArray[i]) {
                    // var decoded = ethUtil.rlp.decode(d);
                    var decoded = d;
                    var fieldArray = [];
                    decoded.forEach(function(elem) {
                        var cl = self._classes[i];
                        fieldArray.push(new cl(elem));
                    });
                    self[self._fields[i]] = fieldArray;
                } else {
                    var cl = self._classes[i];
                    self[self._fields[i]] = new cl(d);
                }
            } else {
                self[self._fields[i]] = ethUtil.toBuffer(d);
            }
        })
      } else if (typeof data === 'object') {
        const keys = Object.keys(data)
        fields.forEach(function (field) {
          if (keys.indexOf(field.name) !== -1) self[field.name] = data[field.name]
          if (keys.indexOf(field.alias) !== -1) self[field.alias] = data[field.alias]
        })
      } else {
        throw new Error('invalid data')
      }
    }

  }