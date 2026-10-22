import { formatUpdate } from "./version.js";

const [current = "1.2.3", next = "2.0.0"] = process.argv.slice(2);

console.log(formatUpdate(current, next));
