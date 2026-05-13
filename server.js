const fetch = require('node-fetch');
const express = require('express');

const app = express();

app.use(express.json());
app.use(express.static('public'));

app.post('/deploy', async (req, res) => {

    try {

        const config = req.body;

        console.log("Deploy Request:", config);

        const response = await fetch('http://hypervhost:8099/deploy', {

            method: 'POST',

            headers: {
                'Content-Type': 'application/json'
            },

            body: JSON.stringify(config)

        });

        console.log("Hyper-V Response:", response.status);

        res.json({
            status: 'Deployment gestartet'
        });

    }
    catch (err) {

        console.error("FEHLER:", err);

        res.status(500).json({
            error: err.toString()
        });
    }

});

app.listen(3000, () => {

    console.log('VM Portal läuft auf Port 3000');

});