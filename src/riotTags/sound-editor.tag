sound-editor.panel.view
    .modal
        b {voc.name}
        br
        input.wide(type="text" value="{sound.name}" onchange="{wire('this.sound.name')}")
        .anErrorNotice(if="{nameTaken}") {vocGlob.nametaken}
        br
        p 
            label
                b {voc.poolSize}   
                input(type="number" min="1" max="32" value="{sound.poolSize || 5}" onchange="{wire('this.sound.poolSize')}")
        audio(
            if="{!loadingAudio && audioBlob}"
            src="{getAudioSrc()}"
            ref="audio" controls loop 
        )
        p(if="{loadingAudio}")
            label
                span {voc.loadingAudio}
        p(if="{audioBlob}")
            label
                b {voc.encodingQuality}
                input(type="number" min="0", max="100" value="{this.encodingQuality}" onchange="{changeEncodingQuality}" placeholder="%")
        p(if="{audioBlob}")
            label.checkbox
                input(type="checkbox" checked="{sound.isMusic}" onchange="{wire('this.sound.isMusic')}") 
                span   {voc.isMusicFile}
        p(if="{audioBlob}")
            label
                input(type="checkbox" checked="{toTrim}" onchange="{changeToTrim}")
                span   {voc.toTrim}
        p(if="{toTrim}")
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
        
        this.namespace = 'soundview';
        this.mixin(window.riotVoc);
        this.mixin(window.riotWired);
        this.toTrim = false;
        this.trimThreshold = 5; // this default value come from different manual testing on different audio source.
        this.sound = this.opts.sound;
        this.audioBuffer = null;
        this.audioBlob = null; 
        this.encodingQuality = 80;
        this.loadingAudio = false;

        this.on('mount', ()=>{
            // at init, if the sound already exist, we read the file into a binary array to allow memory changes (such as trim)
            if (this.sound.lastmod) {
                this.loadingAudio = true;
                this.getAudioBuffer('file://' + sessionStorage.projdir + '/snd/' + this.sound.origname + '?' + this.sound.lastmod).then((buffer) => {
                    this.audioBuffer = buffer;
                    this.applySoundTransformation();
                });
            }
        });

        this.getAudioSrc = () => {
            return URL.createObjectURL(this.audioBlob);
        };

        this.audioBufferToOggBlob = (audioBuffer) => {
            return new Promise((resolve, reject) => {
                var myWorker = new Worker('data/libvorbis.js');
                var chunks = [];
                var samples = audioBuffer.length;
                var channels = audioBuffer.numberOfChannels;
                var sampleRate = audioBuffer.sampleRate;
                var chunkSize = 10 * 4096;
                
                
                myWorker.onmessage = function(e) {
                    var data = e.data;
                    switch(data.type) {
                        case 'data':
                            chunks.push(data.buffer);
                            break;
                        case 'finish':
                            var blob = new Blob(chunks, { type: 'audio/ogg' });
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
                    var buffers = [];
                    var samples = audioBuffer.length;
                    var channels = audioBuffer.numberOfChannels;
                    for (var ch = 0; ch < channels; ++ch) {
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
                
                
                var ctx = new AudioContext();
                
                for (var n = 0; n < samples; n += chunkSize) {
                    var actualSize = Math.min(chunkSize, samples - n - 1);
                    var chunkBuffer = ctx.createBuffer(channels, actualSize, ctx.sampleRate);
                    for (var ch = 0; ch < channels; ch += 1) {
                        var src  = audioBuffer.getChannelData(ch).subarray(n, n + actualSize);
                        var dest = chunkBuffer.getChannelData(ch);
                        dest.set(src);
                    }	
                    encode(chunkBuffer);
                }
                
                myWorker.postMessage({ type: 'finish' });
            });
        };

        this.on('update', () => {
            if (window.currentProject.sounds.find(sound => 
                this.sound.name === sound.name && this.sound !== sound
            )) {
                this.nameTaken = true;
            } else {
                this.nameTaken = false;
            }            
        });

        // take an Audio Buffer and return a trimmed buffer according to the threshold
        this.trimAudioBuffer = (audioBuffer) => {
            let threshold = this.trimThreshold / 1000;
            let firsts = [];
            let lasts = [];           
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

        this.soundSave = e => {
            this.refs.audio.pause();
            this.parent.editing = false;
            this.sound.origname = 's' + this.sound.uid + '.ogg';
            this.sound.lastmod = +(new Date());
 
            // save the OGG file locally
            var fileReader = new FileReader();
            fileReader.onload = () => {
                fs.writeFileSync(sessionStorage.projdir + '/snd/s' + this.sound.uid + '.ogg', Buffer(new Uint8Array(fileReader.result)));
            };
            fileReader.readAsArrayBuffer(this.audioBlob);

            // if we detect a same file but with a different extension, we remove it since the sound is migrated
            fs.readdir(sessionStorage.projdir + '/snd/', (err, files) => {
                files.filter(file => file.indexOf('s' + this.sound.uid) !== -1 && file.indexOf('.ogg') === -1).forEach(f => {
                    fs.unlink(sessionStorage.projdir + '/snd/' + f, (err) =>{ if(err) throw err});
                });
            });

            this.parent.update();
        };

        this.changeSoundFile = () => {
            this.loadingAudio = true;
            this.update();
            // we load a file, get the binary data
            this.getAudioBuffer(this.refs.inputsound.value).then((buffer) => {
                this.audioBuffer = buffer;
                this.applySoundTransformation();
                if (!this.sound.lastmod && this.sound.name === 'Sound_' + this.sound.uid.split('-').pop()) {
                        this.sound.name = path.basename(this.refs.inputsound.value, path.extname(this.refs.inputsound.value));
                }
                this.refs.inputsound.value = '';
                this.update();
            });
        };

        this.applySoundTransformation = ()=>{
            this.loadingAudio = true;
            this.audioBufferToOggBlob(this.toTrim ? this.trimAudioBuffer(this.audioBuffer) : this.audioBuffer).then(
                (blob)=>{
                    this.audioBlob = blob;
                    this.loadingAudio = false;
                    this.update();
                }
            );
        };

        this.getAudioBuffer = (audioUrl) => {
            return new Promise((resolve, reject) => {
                var context = new AudioContext();
                var request = new XMLHttpRequest();
                request.open('GET', audioUrl, true);
                request.responseType = 'arraybuffer';
                // Decode asynchronously
                request.onload = () => {
                    context.decodeAudioData(request.response, function(buffer) {
                    resolve(buffer);
                    }, ()=> {reject()});
                }
                request.send();
            });
        };
        this.changeToTrim = (e) => {
            this.toTrim = e.srcElement.checked;
            this.applySoundTransformation();
        };
        this.changeTrimThreshold = (e) => {
            this.trimThreshold = e.srcElement.value;
            this.applySoundTransformation();
        }
        this.changeEncodingQuality = (e) => {
            this.encodingQuality = e.srcElement.value;
            this.applySoundTransformation();          
        }