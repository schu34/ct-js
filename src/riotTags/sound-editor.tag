sound-editor.panel.view
    .modal
        b {voc.name}
        br
        input.wide(type="text" value="{sound.name}" onchange="{wire('this.sound.name')}")
        .anErrorNotice(if="{nameTaken}") {vocGlob.nametaken}
        audio(
            if="{!loadingAudio && audioSrc}"
            src="{audioSrc}"
            ref="audio" controls loop 
        )
        p(if="{!loadingAudio && audioSrc}")
            label
                b {voc.poolSize}   
                input(type="number" min="1" max="32" value="{sound.poolSize || 5}" onchange="{wire('this.sound.poolSize')}")
        p(if="{loadingAudio}")
            label
                span {voc.loadingAudio}
        p(if="{!loadingAudio && audioSrc}")
            label
                b {voc.encodingQuality}
                input(type="number" min="0" max="100" value="{this.encodingQuality}" onchange="{wire('this.encodingQuality')}" placeholder="%")
        p(if="{!loadingAudio && audioSrc}")
            label.checkbox
                input(type="checkbox" checked="{sound.isMusic}" onchange="{wire('this.sound.isMusic')}") 
                span   {voc.isMusicFile}
        p(if="{!loadingAudio && audioSrc}")
            label
                input(type="checkbox" checked="{toTrim}" onchange="{changeToTrim}")
                span   {voc.toTrim}
        p(if="{!loadingAudio && audioSrc && toTrim}")
            label
                b {voc.trimThreshold}
                i.icon-info.aLittleHint(title="{voc.trimThresholdHint}")
                input(type="number" min="0" max="999" value="{trimThreshold}" onchange="{changeTrimThreshold}")
        label.file
            .button.wide.nml
                i.icon.icon-plus
                span {voc.import}
            input(type="file" ref="inputsound" accept="audio/*" onchange="{changeSoundFile}")
        p.nmb
            button.wide(onclick="{soundSave}")
                i.icon.icon-confirm
                span {voc.save}
    script.
        const path = require('path');
        const fs = require('fs');
        const lamejs = require('lamejs');

        this.audioSrc = null;
        this.namespace = 'soundview';
        this.mixin(window.riotVoc);
        this.mixin(window.riotWired);
        this.toTrim = false;
        this.trimThreshold = 5; // this default value come from different manual testing on different audio source.
        this.sound = this.opts.sound;
        this.audioBuffer = null;
        this.encodingQuality = 80;
        this.loadingAudio = false;
        this.hasChanged = false;

        this.on('mount', ()=>{
            // at init, if the sound already exist, we read the file into a binary array to allow memory changes (such as trim)
            if (this.sound.lastmod) {
                this.audioSrc = 'file://' + sessionStorage.projdir + '/snd/' + this.sound.origname + '.wav?'+ this.sound.lastmod;
            }
        });

        // private

        this.getAudioBuffer = (audioUrl) => {
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
                        reject()});
                });         
            });
        };

        this.trimAudioBuffer = (audioBuffer) => {
            let threshold = this.trimThreshold / 1000;
            let firsts = [];
            let lasts = [];
            this.hasChanged = true;
            // we detect the empty sound at the begining of the file 
            for (let c = 0; c < audioBuffer.numberOfChannels; c++) {
                let data = audioBuffer.getChannelData(c);
                for (let i = 0; i < data.length; i++) {
                    if (Math.abs(data[i]) > threshold) {
                        firsts.push(i);
                        break;
                    }
                }
            }
            // same process but we start at the end of the file
            for (let c = 0; c < audioBuffer.numberOfChannels; c++) {
                let data = audioBuffer.getChannelData(c);
                for (let i = data.length; i >= 0; i--) {
                    if (Math.abs(data[i]) > threshold) {
                        lasts.push(i);
                        break;
                    }
                }
            }
            // now we can cut the buffer starting from MIN(firsts) and MAX(lasts)
            let newBuffer = new AudioContext().createBuffer(audioBuffer.numberOfChannels, Math.max.apply(null, lasts)-Math.min.apply(null, firsts), audioBuffer.sampleRate); 
            for (let c = 0; c < audioBuffer.numberOfChannels; c++) {
                let data = audioBuffer.getChannelData(c);
                let clearedData = data.slice(Math.min.apply(null, firsts), Math.max.apply(null, lasts));
                newBuffer.copyToChannel(clearedData, c, 0); 
            }
            return newBuffer;
        };  

        this.convertToWav = (abuffer) => {	
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

        this.convertToOggVorbis = (audioBuffer) => {
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

        this.convertToMp3 = (audioBuffer) => {
            return new Promise((resolve, reject) => {

                let mp3Data = [];
                let samples = audioBuffer.length;
                let channels = audioBuffer.numberOfChannels;
                let sampleBlockSize = 1152;
                let mp3encoder = new lamejs.Mp3Encoder(channels, 44100, 320); // 44.1khz encode to 320kbps
                
                console.log(channels);
                for (let i = 0; i < samples; i += sampleBlockSize) {
                    let leftChunk = audioBuffer.getChannelData(0).subarray(i, i + sampleBlockSize);
                    let rightChunk = channels === 2 ? audioBuffer.getChannelData(1).subarray(i, i + sampleBlockSize) : [];
                    let mp3buf = mp3encoder.encodeBuffer(leftChunk, rightChunk);
                    if (mp3buf.length > 0) {
                        mp3Data.push(mp3buf);
                    }
                }
                let mp3buf = mp3encoder.flush();   //finish writing mp3
                if (mp3buf.length > 0) {
                    mp3Data.push(mp3buf);
                }
                console.log(mp3Data);

                let blob = new Blob(mp3Data, { type: 'audio/mp3' });
                resolve(blob);
            });
        };

        this.updateAudioSrc = () => {
            this.convertToWav(this.toTrim ? this.trimAudioBuffer(this.audioBuffer) : this.audioBuffer).then((audioBlob) => { 
                this.loadingAudio = false;
                this.audioSrc =  URL.createObjectURL(audioBlob);
                this.update();
            });
        };

        // public
        this.changeSoundFile = () => {
            this.loadingAudio = true;
            this.update();
            // we load a file, get the binary data
            this.getAudioBuffer(this.refs.inputsound.value).then((buffer) => {
                this.hasChanged = true;
                this.audioBuffer = buffer;
                if (!this.sound.lastmod && this.sound.name === 'Sound_' + this.sound.uid.split('-').pop()) {
                        this.sound.name = path.basename(this.refs.inputsound.value, path.extname(this.refs.inputsound.value));
                }
                this.refs.inputsound.value = '';
                this.updateAudioSrc();
                this.update();
            });
        };

        this.changeToTrim = (e) => {
            this.toTrim = e.srcElement.checked;
            this.hasChanged = true;

            // we attempt to make a change. Load the buffer if not available.
            if (this.audioBuffer == null) {
                this.loadingAudio = true;
                this.getAudioBuffer(sessionStorage.projdir + '/snd/' + this.sound.origname + '.wav').then((buffer) => {
                    this.audioBuffer = buffer;
                    this.loadingAudio = false;
                    this.updateAudioSrc();
                });
            }
            else {
                this.updateAudioSrc();
            }
        };

        this.changeTrimThreshold = (e) => {
            this.trimThreshold = e.srcElement.value;
            this.updateAudioSrc();
        }

        this.on('update', () => {
            if (window.currentProject.sounds.find(sound => 
                this.sound.name === sound.name && this.sound !== sound
            )) {
                this.nameTaken = true;
            } else {
                this.nameTaken = false;
            }            
        });        

        this.soundSave = e => {
            this.refs.audio.pause();
            this.parent.editing = false;
            this.sound.origname = 's' + this.sound.uid;
            this.sound.lastmod = +(new Date());

            // if there is a change or if it's a new audio, convert to wav/ogg/mp3 and save it in the file system
            if (this.hasChanged) {     
                console.log('save');
                let bufferToSave = this.toTrim ? this.trimAudioBuffer(this.audioBuffer) : this.audioBuffer;               
                this.convertToWav(bufferToSave).then((wavBlob)=> {
                    let fileReader = new FileReader();
                    fileReader.onload = () => {
                        fs.writeFileSync(sessionStorage.projdir + '/snd/s' + this.sound.uid + '.wav', Buffer(new Uint8Array(fileReader.result)));
                    };
                    fileReader.readAsArrayBuffer(wavBlob); 
                });

                this.convertToOggVorbis(bufferToSave).then((oggBlob)=> {
                    let fileReader = new FileReader();
                    fileReader.onload = () => {
                        fs.writeFileSync(sessionStorage.projdir + '/snd/s' + this.sound.uid + '.ogg', Buffer(new Uint8Array(fileReader.result)));
                    };
                    fileReader.readAsArrayBuffer(oggBlob); 
                });

                /*
                this.convertToMp3(this.audioBuffer).then((mp3Blob)=> {
                    let fileReader = new FileReader();
                    fileReader.onload = () => {
                        fs.writeFileSync(sessionStorage.projdir + '/snd/s' + this.sound.uid + '.mp3', Buffer(new Uint8Array(fileReader.result)));
                    };
                    fileReader.readAsArrayBuffer(mp3Blob); 
                });
                */
            }                      

            this.parent.update();
        };