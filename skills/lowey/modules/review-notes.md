# Review notes (Maquette 0.26)

A note is a pin stuck on a spot of the scene: on a thing it rides with the thing when it moves; at a point it stays
there. Notes live in the project file, signed by whoever wrote them, and are answered in place on the iPad (Actions ▸
Notes shows the pins; a pin's tap opens its thread). People review together over FaceTime: every note written,
answered or resolved reaches everyone. Use notes to leave feedback or a to-do on a shot, not to explain your build.

```json
{"do":"note","text":"Make the back 10 cm taller","on":"Chair"}
{"do":"note","text":"A window here?","at":[0,1.5,-3]}
{"do":"note","op":"list"}
{"do":"note","op":"reply","note":1,"text":"Done: 0.9 m now"}
{"do":"note","op":"resolve","note":1}
{"do":"note","op":"reopen","note":"<id>"}
{"do":"note","op":"delete","note":2}
```

- `on` puts the pin at the top middle of the thing unless `at` says where; `at` alone is a spot in the world.
- `note` is the number in the list (from 1, the order `list` reports) or the id it shows in brackets.
- `list` reports every note: its number, id, the thing, open or resolved, who wrote what and the replies.
- Notes are signed "Assistant" unless `author` says otherwise. Don't sign as Hesham or anyone else.
- `time` (seconds) ties a note to a moment of the film; opening it on the iPad goes there.
- An answer opens a resolved note again: there's something new to read.
- Present mode, the iPhone companion and reviews over FaceTime are the person's to start on the iPad; there are no verbs
  for them.
