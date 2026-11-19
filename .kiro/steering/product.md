---
inclusion: always
---

# Product: Sounder

## One sentence
Tap the first letter of each word in Morse code with one button; Sounder says the whole sentence aloud.

## Who it is for
Literate people who cannot speak or type but can make one reliable movement (a press, a puff, a blink):
people with ALS, cerebral palsy, spinal injury, stroke, or temporary loss of speech. Also their families
and speech-language therapists. Design persona: Mariam, 54, living with ALS, presses one button with her thumb.
She is a persona, not a real user. Never present her as one.

## The problem
With one switch, every letter costs several presses, and every press costs effort and time.
Existing Morse tools stop at letters or single-word prediction.

## How it works
1. Press: short = dit, long = dah. Two-switch mode: one key each.
2. Decode: the engine classifies presses against the user's own calibrated rhythm.
3. Shorthand mode: the user enters one initial per word. Spell mode: every letter.
4. Expand: a language model proposes up to 4 sentences. Every candidate must start each word
   with the typed initials, in order. Invalid candidates are discarded before display.
5. Choose: dit = next candidate, dah = speak it.
6. Refine: add letters to a word, or switch to Spell mode. There is never a dead end.
7. Speak: the platform voice says the sentence.

## Design principles (apply to every change)
1. Every press gives immediate visible and audible feedback.
2. Count presses, then remove them. Every flow has a press budget.
3. Nothing depends on timing except the key itself: no menu timeouts, no disappearing messages.
4. The words belong to the user: nothing is ever spoken unless the user selected it.
5. Calm over clever: nothing on screen moves by itself.

## Scope for the hackathon (deadline: submit Dec 3, 2026)
In: Morse engine, adaptive timing, one- and two-switch input, Key screen, Shorthand expansion,
Spell mode with undo, speech, guided first run, offline phrase index, presses-saved meter,
switch scanning, phrases and history screen. Web build only, hosted, no login.

Out (do not build): accounts or cloud sync, voice cloning, symbol boards, eye tracking,
fine-tuned models, Android or iOS builds, conversation listening, payments, analytics, ads.

## Privacy and ethics
- Phrases, history and settings stay on the device. No accounts.
- Cloud expansion sends only initials and recent sentences, is opt-in, and the server stores nothing.
- Sounder is a communication aid, not a medical device. Make no clinical claims.