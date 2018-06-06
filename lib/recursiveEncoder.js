const ethUtil = require('ethereumjs-util')
const assert = require('assert');
const isBuffer = require('is-buffer')

exports.defineProperties = function (self, fields, data_) {
    self._raw = []
    self._fields = []
    self._classes = []
    self._isArray = []
  
    /**
     * Computes a sha3-256 hash of the serialized object
     * @return {Buffer}
     */
    self.hash = function () { 
        const rlpEncoded = self.rlpEncode();
        return ethUtil.hashPersonalMessage(rlpEncoded);
      }


    // attach the `toJSON`
    self.toJSON = function (label) {
      if (label) {
        const obj = {}
        self._fields.forEach(function (field) {
          if (!self[field] || typeof self[field] === "undefined"){
            return;
          }
          if (isBuffer(self[field])) {
            obj[field] = '0x' + self[field].toString('hex');
            return;
          } else if (self[field].toJSON !== undefined) {
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
    }

    self.rlpEncode = function rlpEncode() {
        return ethUtil.rlp.encode(self.raw)
    }
  
    Object.defineProperty(self, 'raw', {
        enumerable: true,
        configurable: false,
        get: function() {
            const toReturn = [];
            self._raw.forEach(function (rawItem, i) {
                if (isBuffer(self._raw[i])) {
                    toReturn.push(self._raw[i]);
                } else if (self._raw[i].constructor.name === "Array") {
                    const items = [];
                    self._raw[i].forEach(function(subitem, j) {
                      if (subitem.raw !== undefined) {
                        items.push(subitem.raw)
                      } else {
                        items.push(subitem)
                      }
                    });
                    toReturn.push(items);
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
      const isArray = field.array ? true: false;
      self._isArray.push(isArray);
      const envelope = field.envelope ? true : false; 

      function getter () {
          return self._raw[i];
      }
      function setter (v_) {
        let v = v_;
          if (envelope) {
              if (isArray) {
                assert(v.constructor.name === "Array", 'The field ' + field.name + ' must be an array')
              }
              self._raw[i] = v;
              return;
          }

        let vBuffer = ethUtil.toBuffer(v);
  
        if (vBuffer.toString('hex') === '00' && !field.allowZero) {
          vBuffer  = Buffer.alloc(0);
        }
  
        if (field.allowLess && field.length !== undefined) {
          const strippedvBuffer = ethUtil.stripZeros(vBuffer)
          self._raw[i] = strippedvBuffer;
          assert(field.length >= v.length, 'The field ' + field.name + ' must not have more ' + field.length + ' bytes')
        } else if (!(field.allowZero && vBuffer.length === 0) && field.length !== undefined) {
          assert(field.length === vBuffer.length, 'The field ' + field.name + ' must have byte length of ' + field.length)
          self._raw[i] = vBuffer;
        }

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
    if (data_ !== undefined) {
      let data = data_;
      if (typeof data === 'string' || isBuffer(data)) {
        data = ethUtil.rlp.decode(data);
      }
 
      if (Array.isArray(data)) {
        if (data.length > self._fields.length) {
          throw (new Error('wrong number of fields in data'))
        }
  
        // make sure all the items are buffers
        data.forEach(function (d, i) {
            if (typeof self._classes[i] !== "undefined") {
                if (self._isArray[i]) {
                    const decoded = d;
                    const fieldArray = [];
                    decoded.forEach(function(elem) {
                        let cl = self._classes[i];
                        fieldArray.push(new cl(elem));
                    });
                    self[self._fields[i]] = fieldArray;
                } else {
                    let cl = self._classes[i];
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