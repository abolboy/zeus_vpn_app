Map<String, dynamic> _noiseMask() {
  final isStr = _patt.noiseType == 'str';
  final entry = <String, dynamic>{
    if (isStr) 'str': _patt.noisePacket else 'rand': _range(_patt.noisePacket, '10-20', min: 1),
    'delay': _range(_patt.noiseDelay, '10-20'),
  };
  return {
    'type': 'noise',
    'settings': {'reset': '30-60', 'noise': [entry]},
  };
}
