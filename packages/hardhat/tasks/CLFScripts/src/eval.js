await import('npm:ethers@6.10.0');
const h = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(secrets.SRC_JS));
const hex = Array.from(new Uint8Array(h))
	.map(b => ('0' + b.toString(16)).slice(-2))
	.join('');
if ('0x' + hex === args[0]) return await eval(secrets.SRC_JS);
throw new Error(`0x${hex},${args[0]}`);
