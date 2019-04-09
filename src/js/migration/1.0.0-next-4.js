try { if (migration_process == undefined) { migration_process = [];}}
catch {migration_process = [];}

/* CHANGELOG
 * Convert all audio sound to WAV/OGG/MP3 and change the origname to match the new system
 */

migration_process.push({version: '1.0.0-next-4', process : async (project) => {
    return new Promise((resolve, reject) => {
         
        // YOUR MIGRATION CODE HERE
        const fs = require('fs');
        let getAudioBuffer = (audioUrl) => {
            return new Promise((resolve, reject) => {            
                let binaryData = new ArrayBuffer();
                let readStream = fs.createReadStream(audioUrl);
                readStream.once('error', err => { reject(err); });
                readStream.on('data', (chunk) => {
                    let chunkArrayBuffer = chunk.buffer.slice(chunk.byteOffset, chunk.byteOffset + chunk.byteLength);
                    // concat two array buffers
                    let tmp = new Uint8Array(binaryData.byteLength + chunkArrayBuffer.byteLength);
                    tmp.set(new Uint8Array(binaryData), 0);
                    tmp.set(new Uint8Array(chunkArrayBuffer), binaryData.byteLength);
                    binaryData = tmp.buffer;
                });
                readStream.on('close', () => {
                    new AudioContext().decodeAudioData(binaryData, (buffer) => {
                        resolve(buffer);
                    }, (err)=>{
                        reject(err)});
                });         
            });
        };
    
        let convertToWav = (abuffer) => {	
            return new Promise((resolve, reject) => {
                let numOfChan = abuffer.numberOfChannels,
                    length = abuffer.length * numOfChan * 2 + 44,
                    buffer = new ArrayBuffer(length),
                    view = new DataView(buffer),
                    channels = [], i, sample,
                    pos = 0,
                    offset = 0;
    
                // write WAVE header
                setUint32(0x46464952);                         // "RIFF"
                setUint32(length - 8);                         // file length - 8
                setUint32(0x45564157);                         // "WAVE"
    
                setUint32(0x20746d66);                         // "fmt " chunk
                setUint32(16);                                 // length = 16
                setUint16(1);                                  // PCM (uncompressed)
                setUint16(numOfChan);
                setUint32(abuffer.sampleRate);
                setUint32(abuffer.sampleRate * 2 * numOfChan); // avg. bytes/sec
                setUint16(numOfChan * 2);                      // block-align
                setUint16(16);                                 // 16-bit (hardcoded in this demo)
    
                setUint32(0x61746164);                         // "data" - chunk
                setUint32(length - pos - 4);                   // chunk length
    
                // write interleaved data
                for(i = 0; i < abuffer.numberOfChannels; i++)
                    channels.push(abuffer.getChannelData(i));
    
                while(pos < length) {
                    for(i = 0; i < numOfChan; i++) {             // interleave channels
                    sample = Math.max(-1, Math.min(1, channels[i][offset])); // clamp
                    sample = (0.5 + sample < 0 ? sample * 32768 : sample * 32767)|0; // scale to 16-bit signed int
                    view.setInt16(pos, sample, true);          // update data chunk
                    pos += 2;
                    }
                    offset++                                     // next source sample
                }
    
                function setUint16(data) {
                    view.setUint16(pos, data, true);
                    pos += 2;
                }
    
                function setUint32(data) {
                    view.setUint32(pos, data, true);
                    pos += 4;
                }
                // create Blob
                resolve(new Blob([buffer], {type: "audio/wav"}));
            });	    
        };
        
        let convertToOggVorbis = (audioBuffer) => {
            return new Promise((resolve, reject) => {
                let myWorker = new Worker('data/libvorbis.js');
                let chunks = [];
                let samples = audioBuffer.length;
                let channels = audioBuffer.numberOfChannels;
                let sampleRate = audioBuffer.sampleRate;
                let chunkSize = 10 * 4096;             
                
                myWorker.onmessage = function(e) {
                    let data = e.data;
                    switch(data.type) {
                        case 'data':
                            chunks.push(data.buffer);
                            break;
                        case 'finish':
                            let blob = new Blob(chunks, { type: 'audio/ogg' });
                            resolve(blob);
                            break;
                    }
                }
    
                // init the encoding
                myWorker.postMessage({
                    type: 'start',
                    sampleRate: sampleRate,
                    channels: channels,
                    quality: this.encodingQuality / 100
                });
                
                function encode(audioBuffer) {
                    let buffers = [];
                    let samples = audioBuffer.length;
                    let channels = audioBuffer.numberOfChannels;
                    for (let ch = 0; ch < channels; ++ch) {
                        // make a copy
                        const array = audioBuffer.getChannelData(ch).slice();
                        buffers.push(array.buffer);
                    }
                    myWorker.postMessage({
                        type: 'data',
                        samples: samples,
                        channels: channels,
                        buffers: buffers
                    }, buffers);
                }
                                
                let ctx = new AudioContext();
                
                for (let n = 0; n < samples; n += chunkSize) {
                    let actualSize = Math.min(chunkSize, samples - n - 1);
                    let chunkBuffer = ctx.createBuffer(channels, actualSize, ctx.sampleRate);
                    for (let ch = 0; ch < channels; ch += 1) {
                        let src  = audioBuffer.getChannelData(ch).subarray(n, n + actualSize);
                        let dest = chunkBuffer.getChannelData(ch);
                        dest.set(src);
                    }	
                    encode(chunkBuffer);
                }
                
                myWorker.postMessage({ type: 'finish' });
            });
        };
    
    
    
        project.sounds.map((sound)=> {
            getAudioBuffer(sessionStorage.projdir + '/snd/' + sound.origname).then((buffer) => {
                
                convertToWav(buffer).then((wavBlob)=> {
                    let fileReader = new FileReader();
                    fileReader.onload = () => {
                        fs.writeFileSync(sessionStorage.projdir + '/snd/s' + sound.uid + '.wav', Buffer(new Uint8Array(fileReader.result)));
                    };
                    fileReader.readAsArrayBuffer(wavBlob); 
                });
    
                convertToOggVorbis(buffer).then((oggBlob)=> {
                    let fileReader = new FileReader();
                    fileReader.onload = () => {
                        fs.writeFileSync(sessionStorage.projdir + '/snd/s' + sound.uid + '.ogg', Buffer(new Uint8Array(fileReader.result)));
                    };
                    fileReader.readAsArrayBuffer(oggBlob); 
                });
                sound.origname = sound.origname.split('.')[0];
                resolve()
            }, (err) => {reject(err)});
        }); 


    })
}});


