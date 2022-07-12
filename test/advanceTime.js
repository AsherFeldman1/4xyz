async function advanceTime(time) {
	await network.provider.send("evm_increaseTime", [time]);
}

async function advanceBlock() {
	await network.provider.send("evm_mine");
}

async function advanceTimeAndBlock(time) {
	await advanceTime(time);
	await advanceBlock();
}

async function advanceBlocks(blocks) {
	let promiseArr = new Array(blocks);
	for (let i = 0; i < blocks; i++) {
		promiseArr[i] = network.provider.send("evm_mine");
	}
	await Promise.all(promiseArr);
}

module.exports = {
	advanceTime,
	advanceBlock,
	advanceBlocks,
	advanceTimeAndBlock
}