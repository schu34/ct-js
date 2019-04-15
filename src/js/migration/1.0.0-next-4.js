window.migrationProcess = window.migrationProcess || [];

/* CHANGELOG
 * Convert all audio sound to WAV/OGG/MP3 and change the origname to match the new system
 */

window.migrationProcess.push({
    version: '1.0.0-next-4',
    process: project => new Promise((resolve, reject) => {
         
        // YOUR MIGRATION CODE HERE
        const fs = require('fs');
        const getAudioBuffer = (audioUrl) => new Promise((resolve, reject) => {            
            let binaryData = new ArrayBuffer();
            const readStream = fs.createReadStream(audioUrl);
            readStream.once('error', err => { reject(err); });
            readStream.on('data', (chunk) => {
                const chunkArrayBuffer = chunk.buffer.slice(chunk.byteOffset, chunk.byteOffset + chunk.byteLength);
                // concat two array buffers
                const tmp = new Uint8Array(binaryData.byteLength + chunkArrayBuffer.byteLength);
                tmp.set(new Uint8Array(binaryData), 0);
                tmp.set(new Uint8Array(chunkArrayBuffer), binaryData.byteLength);
                binaryData = tmp.buffer;
            });
            readStream.on('close', () => {
                new AudioContext().decodeAudioData(binaryData, (buffer) => {
                    resolve(buffer);
                }, reject);
            });         
        });

        const convertToWav = (abuffer) => new Promise((resolve, reject) => {
            const numOfChan = abuffer.numberOfChannels,
                  length = abuffer.length * numOfChan * 2 + 44,
                  buffer = new ArrayBuffer(length),
                  view = new DataView(buffer),
                  channels = [];
            var i, sample,
                pos = 0,
                offset = 0;
            var setUint16 = function(data) {
                view.setUint16(pos, data, true);
                pos += 2;
            };
            var setUint32 = function(data) {
                view.setUint32(pos, data, true);
                pos += 4;
            };
    
            // write WAVE header
            setUint32(0x46464952); // "RIFF"
            setUint32(length - 8); // file length - 8
            setUint32(0x45564157); // "WAVE"

            setUint32(0x20746d66); // "fmt " chunk
            setUint32(16); // length = 16
            setUint16(1); // PCM (uncompressed)
            setUint16(numOfChan);
            setUint32(abuffer.sampleRate);
            setUint32(abuffer.sampleRate * 2 * numOfChan); // avg. bytes/sec
            setUint16(numOfChan * 2); // block-align
            setUint16(16); // 16-bit (hardcoded in this demo)

            setUint32(0x61746164); // "data" - chunk
            setUint32(length - pos - 4); // chunk length

            // write interleaved data
            for (i = 0; i < abuffer.numberOfChannels; i++) {
                channels.push(abuffer.getChannelData(i));
            }

            while (pos < length) {
                for (i = 0; i < numOfChan; i++) { // interleave channels
                sample = Math.max(-1, Math.min(1, channels[i][offset])); // clamp
                // eslint-disable-next-line no-bitwise
                sample = (0.5 + sample < 0 ? sample * 32768 : sample * 32767)|0; // scale to 16-bit signed int
                view.setInt16(pos, sample, true); // update data chunk
                pos += 2;
                }
                offset++; // next source sample
            }

            // create Blob
            resolve(new Blob([buffer], {type: 'audio/wav'}));
        });
        
        const convertToOggVorbis = (audioBuffer) => new Promise((resolve, reject) => {
                const myWorker = new Worker('data/libvorbis.js');
                const chunks = [];
                const samples = audioBuffer.length;
                const channels = audioBuffer.numberOfChannels;
                const {sampleRate} = audioBuffer;
                const chunkSize = 10 * 4096;             
                
                myWorker.onmessage = function(e) {
                    const {data} = e;
                    if (data.type === 'data') {
                        chunks.push(data.buffer);
                    } else if (data.type === 'finish') {
                        const blob = new Blob(chunks, {type: 'audio/ogg'});
                        resolve(blob);
                    }
                };
    
                // init the encoding
                myWorker.postMessage({
                    type: 'start',
                    sampleRate,
                    channels,
                    quality: this.encodingQuality / 100
                });
                
                var encode = function (audioBuffer) {
                    const buffers = [];
                    const samples = audioBuffer.length;
                    const channels = audioBuffer.numberOfChannels;
                    for (let ch = 0; ch < channels; ++ch) {
                        // make a copy
                        const array = audioBuffer.getChannelData(ch).slice();
                        buffers.push(array.buffer);
                    }
                    myWorker.postMessage({
                        type: 'data',
                        samples,
                        channels,
                        buffers
                    }, buffers);
                };
                                
                const ctx = new AudioContext();
                
                for (let n = 0; n < samples; n += chunkSize) {
                    const actualSize = Math.min(chunkSize, samples - n - 1);
                    const chunkBuffer = ctx.createBuffer(channels, actualSize, ctx.sampleRate);
                    for (let ch = 0; ch < channels; ch += 1) {
                        const src = audioBuffer.getChannelData(ch).subarray(n, n + actualSize);
                        const dest = chunkBuffer.getChannelData(ch);
                        dest.set(src);
                    }
                    encode(chunkBuffer);
                }
                
                myWorker.postMessage({type: 'finish'});
            });
    
        // TODO resolve migration's promise after converting all the sounds
        project.sounds.map(sound => {
            getAudioBuffer(sessionStorage.projdir + '/snd/' + sound.origname).then((buffer) => {
                
                convertToWav(buffer).then(wavBlob => {
                    const fileReader = new FileReader();
                    fileReader.onload = () => {
                        fs.writeFileSync(sessionStorage.projdir + '/snd/s' + sound.uid + '.wav', new Uint8Array(fileReader.result));
                    };
                    fileReader.readAsArrayBuffer(wavBlob); 
                });
    
                convertToOggVorbis(buffer).then(oggBlob => {
                    const fileReader = new FileReader();
                    fileReader.onload = () => {
                        fs.writeFileSync(sessionStorage.projdir + '/snd/s' + sound.uid + '.ogg', new Uint8Array(fileReader.result));
                    };
                    fileReader.readAsArrayBuffer(oggBlob); 
                });
                [sound.origname] = sound.origname.split('.');
                resolve();
            }, (err) => {reject(err);});
        }); 

    })
});


