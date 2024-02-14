var canvas;
var ctx;
var wasm;

function platform_draw_rect(x, y, width, height, rgba) {
		ctx.fillStyle = color_hex(rgba);
		ctx.strokeRect(x, y, width, height);
}

function platform_fill_rect(x, y, width, height, rgba) {
		ctx.fillStyle = color_hex(rgba);
		ctx.fillRect(x, y, width, height);
}

function platform_fill_text(x, y, text_ptr, rgba) {
		const buffer = wasm.instance.exports.memory.buffer;
		const text = cstr_by_ptr(buffer, text_ptr);

		ctx.font = "28px sans-serif";
		ctx.fillStyle = color_hex(rgba);
		// ctx.textAlign = "center";
		// ctx.textBaseline = "middle";
		ctx.fillText(text, x, y);
}

const imports = {
		env: {
			platform_draw_rect,
			platform_fill_rect,
			platform_fill_text,
		}
}

window.document.body.onload = function() {
		canvas = document.querySelector("canvas");
		ctx = canvas.getContext("2d");

		WebAssembly
			 .instantiateStreaming(fetch("zig-out/lib/game.wasm"), imports)
			 .then(function(source) {
					wasm = source;
				  const { exports } = source.instance;

					document.addEventListener('keydown', function(event) {
							exports.Handle_Key_Down(keycode(event.key));
					});

					exports.Game_Init(BigInt(Date.now()));
					exports.Try_Spawn_Next_Mino();

					window.requestAnimationFrame(mainloop);
		 })
};

function mainloop() {
		const { exports } = wasm.instance;

		ctx.clearRect(0, 0, canvas.width, canvas.height);
		ctx.fillStyle = 'black';
		ctx.fillRect(0, 0, canvas.width, canvas.height);

		exports.Update_Game_State();
		exports.Render_Game_State();

		window.requestAnimationFrame(mainloop);
}

function keycode(key) {
		switch (key) {
				case ' ': {
						return 32;
				}
				case 'ArrowRight': {
						return 1073741903
				}
				case 'ArrowLeft': {
						return 1073741904;
				}
				case 'ArrowDown': {
						return 1073741905
				}
				case 'ArrowUp': {
						return 1073741906
				}
		}
}

function color_hex(color) {
	  const r = ((color>>(3*8))&0xFF).toString(16).padStart(2, '0');
	  const g = ((color>>(2*8))&0xFF).toString(16).padStart(2, '0');
	  const b = ((color>>(1*8))&0xFF).toString(16).padStart(2, '0');
	  const a = ((color>>(0*8))&0xFF).toString(16).padStart(2, '0');
	  return "#"+r+g+b+a;
}

function cstrlen(mem, ptr) {
    let len = 0;
    while (mem[ptr] != 0) {
        len++;
        ptr++;
    }
    return len;
}

function cstr_by_ptr(mem_buffer, ptr) {
    const mem = new Uint8Array(mem_buffer);
    const len = cstrlen(mem, ptr);
    const bytes = new Uint8Array(mem_buffer, ptr, len);
    return new TextDecoder().decode(bytes);
}
