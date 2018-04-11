let fs = require('fs');
let contract = require("../build/contracts/PlasmaParent.json");
let details = {error: false, address: contract.networks[4].address, abi: contract.abi};
fs.writeFile("../build/details", JSON.stringify(details), err => {
	    if (err) throw err;
	    console.log('Complete. Contract address: ' + details.address);
	}
);
