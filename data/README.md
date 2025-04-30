# ✈️ OpenFlights Dataset Loader

This folder is used for importing aviation-related data from the [OpenFlights](https://openflights.org/data.html) open database.  
The data includes airports, airlines, routes, aircraft types, and countries.

> ⚠️ To keep the repository lightweight and avoid tracking large or changing data files, the raw `.dat` files are **not included** in this repository and are excluded via `.gitignore`.

---

## 📦 What Data Is Used

The following files are fetched from the OpenFlights GitHub mirror:

- `airports.dat`
- `airlines.dat`
- `routes.dat`
- `planes.dat`
- `countries.dat`

Each file is a UTF-8 encoded, comma-separated `.dat` file.

---

## 📥 How to Download the Data

A helper script `fetchdata.sh` is provided to fetch all files in one go:

```bash
./fetchdata.sh
```
This will download all required .dat files into this folder using curl.

You can also manually download the files from:

📎 https://github.com/jpatokal/openflights/tree/master/data

📄 License
The data is provided under the Open Database License (ODbL).

Please acknowledge OpenFlights in any public use of the dataset.