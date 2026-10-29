// Tablero comercial de EcoBottle.
// Lee los data marts de dw/ y solo busca la fila que corresponde a los filtros:
// todos los KPIs (ventas, ticket, usuarios activos, NPS, ranking) vienen calculados en SQL.

const ARCHIVOS = {
  ventas: "dw/mart_ventas_mensual.csv",
  usuarios: "dw/mart_usuarios_activos_mensual.csv",
  nps: "dw/mart_nps_mensual.csv",
  ranking: "dw/mart_ranking_productos_mensual.csv",
};

const TODOS = "Todos";
const TODAS = "Todas";
const MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
  "agosto", "septiembre", "octubre", "noviembre", "diciembre"];
const MESES_CORTOS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];

const filtros = { mes: TODOS, canal: TODOS, provincia: TODAS, producto: TODOS };
let datos = {};
const graficos = {};

// ---------- Lectura de los CSV ----------

function leerCSV(texto) {
  const [encabezado, ...filas] = texto.trim().split(/\r?\n/);
  const columnas = encabezado.split(",");
  return filas.map((linea) => {
    const valores = linea.split(",");
    const fila = {};
    columnas.forEach((col, i) => {
      const v = valores[i];
      fila[col] = v !== "" && !isNaN(v) ? Number(v) : v;
    });
    return fila;
  });
}

async function cargar() {
  const entradas = await Promise.all(
    Object.entries(ARCHIVOS).map(async ([nombre, ruta]) => {
      const resp = await fetch(ruta);
      if (!resp.ok) throw new Error(`No se pudo leer ${ruta} (${resp.status})`);
      return [nombre, leerCSV(await resp.text())];
    })
  );
  return Object.fromEntries(entradas);
}

// ---------- Formato ----------

const num = (v, dec = 0) =>
  v.toLocaleString("es-AR", { minimumFractionDigits: dec, maximumFractionDigits: dec });
const millones = (v) => `$${num(v / 1e6, 1)} M`;
const miles = (v) => `$${num(v / 1e3, 1)} K`;
const milesSinPeso = (v) => (v >= 1000 ? `${num(v / 1e3, 1)} K` : num(v));
const mesLargo = (m) => { const [a, n] = m.split("-"); return `${MESES[n - 1]} de ${a}`; };
const mesCorto = (m) => { const [a, n] = m.split("-"); return `${MESES_CORTOS[n - 1]} ${a.slice(2)}`; };

const color = (variable) => getComputedStyle(document.documentElement).getPropertyValue(variable).trim();
const colorProducto = (p) => (p.startsWith("Classic") ? color("--classic") : color("--sport"));
const nombreCorto = (p) => p.replace(" Bottle", "");

// ---------- Búsqueda de filas (sin cálculos) ----------

const filaVentas = (f) => datos.ventas.find((r) =>
  r.mes === f.mes && r.canal === f.canal && r.provincia === f.provincia && r.producto === f.producto);
const filaUsuarios = (mes) => datos.usuarios.find((r) => r.mes === mes);
const filaNps = (mes, canal) => datos.nps.find((r) => r.mes === mes && r.canal === canal);

// ---------- Filtros ----------

function opciones(lista, campo, excluir) {
  return [...new Set(lista.map((r) => r[campo]))].filter((v) => v !== excluir).sort();
}

function armarFiltros() {
  const meses = opciones(datos.usuarios, "mes", TODOS);
  const selMes = document.getElementById("f-mes");
  selMes.innerHTML = `<option value="${TODOS}">Todo el período</option>` +
    meses.map((m) => `<option value="${m}">${mesLargo(m)}</option>`).join("");

  const selProv = document.getElementById("f-provincia");
  selProv.innerHTML = `<option value="${TODAS}">Todas</option>` +
    opciones(datos.ventas, "provincia", TODAS).map((p) => `<option value="${p}">${p}</option>`).join("");

  armarSegmentos("f-canal", "canal", [TODOS, ...opciones(datos.ventas, "canal", TODOS)],
    (c) => (c === TODOS ? "Ambos" : c === "Tienda Online" ? "Online" : "Tiendas"));
  armarSegmentos("f-producto", "producto", [TODOS, ...opciones(datos.ventas, "producto", TODOS)],
    (p) => (p === TODOS ? "Todos" : nombreCorto(p)), true);

  selMes.addEventListener("change", (e) => { filtros.mes = e.target.value; dibujar(); });
  selProv.addEventListener("change", (e) => { filtros.provincia = e.target.value; dibujar(); });
  document.getElementById("filtros").addEventListener("reset", () => {
    Object.assign(filtros, { mes: TODOS, canal: TODOS, provincia: TODAS, producto: TODOS });
    setTimeout(dibujar, 0);
  });
}

function armarSegmentos(id, campo, valores, etiqueta, conMuestra = false) {
  const caja = document.getElementById(id);
  valores.forEach((v) => {
    const b = document.createElement("button");
    b.type = "button";
    b.dataset.valor = v;
    if (conMuestra && v !== TODOS) {
      const m = document.createElement("span");
      m.className = "muestra";
      m.style.background = colorProducto(v);
      b.append(m);
    }
    b.append(etiqueta(v));
    b.addEventListener("click", () => { filtros[campo] = v; dibujar(); });
    caja.append(b);
  });
}

function marcarSegmentos() {
  for (const [id, campo] of [["f-canal", "canal"], ["f-producto", "producto"]]) {
    document.querySelectorAll(`#${id} button`).forEach((b) =>
      b.setAttribute("aria-pressed", String(b.dataset.valor === filtros[campo])));
  }
  document.getElementById("f-mes").value = filtros.mes;
  document.getElementById("f-provincia").value = filtros.provincia;
}

// ---------- Titular ----------

function dibujarTitular() {
  const v = filaVentas(filtros);
  const periodo = filtros.mes === TODOS ? "Entre enero de 2024 y septiembre de 2025" : `En ${mesLargo(filtros.mes)}`;
  const h1 = document.getElementById("titular");
  const sub = document.getElementById("hero-sub");

  if (!v) {
    h1.textContent = `${periodo} no hubo ventas con estos filtros`;
    sub.textContent = "Probá con otro período, canal o provincia.";
    return;
  }

  h1.innerHTML = `${periodo} se vendieron <span class="cifra">${millones(v.ventas)}</span>`;

  const partes = [`en ${num(v.pedidos)} pedidos`];
  if (filtros.producto !== TODOS) partes.push(`con la botella ${nombreCorto(filtros.producto)}`);
  if (filtros.canal === "Tienda Online") partes.push("por la tienda online");
  if (filtros.canal === "Tiendas Físicas") partes.push("en las tiendas físicas");
  if (filtros.provincia !== TODAS) partes.push(`en ${filtros.provincia}`);
  sub.textContent = `${partes.join(", ")}. Cada pedido dejó ${miles(v.ticket_promedio)} en promedio.`;
}

// ---------- Botella ----------

const LIQUIDO_ARRIBA = 118;  // altura del líquido dentro del cuerpo de la botella
const LIQUIDO_ABAJO = 422;

function dibujarBotella() {
  const base = { mes: filtros.mes, canal: filtros.canal, provincia: filtros.provincia };
  const productos = opciones(datos.ventas, "producto", TODOS);
  const total = filaVentas({ ...base, producto: TODOS });
  const lista = document.getElementById("mezcla");
  const classic = productos.find((p) => p.startsWith("Classic"));

  const capaClassic = document.getElementById("capa-classic");
  const capaSport = document.getElementById("capa-sport");
  const ola = document.getElementById("ola");

  if (!total) {
    capaClassic.style.transform = capaSport.style.transform = `translateY(${LIQUIDO_ABAJO}px)`;
    ola.style.transform = `translateY(${LIQUIDO_ABAJO}px)`;
    lista.innerHTML = `<li class="vacio">Sin ventas</li>`;
    return;
  }

  // La altura de cada capa es solo la escala del dibujo: ventas del producto sobre el total.
  const ventasClassic = (filaVentas({ ...base, producto: classic }) || { ventas: 0 }).ventas;
  const alto = LIQUIDO_ABAJO - LIQUIDO_ARRIBA;
  const limite = LIQUIDO_ABAJO - alto * (ventasClassic / total.ventas);

  capaSport.style.transform = `translateY(${LIQUIDO_ARRIBA}px)`;
  ola.style.transform = `translateY(${LIQUIDO_ARRIBA}px)`;
  capaClassic.style.transform = `translateY(${limite}px)`;

  const elegido = filtros.producto;
  capaClassic.classList.toggle("apagada", elegido !== TODOS && elegido !== classic);
  capaSport.classList.toggle("apagada", elegido !== TODOS && elegido === classic);
  ola.classList.toggle("apagada", elegido !== TODOS && elegido === classic);

  // Arriba en la lista va el producto que está arriba en la botella.
  lista.innerHTML = [...productos].reverse().map((p) => {
    const fila = filaVentas({ ...base, producto: p });
    return `<li><span class="muestra" style="background:${colorProducto(p)}"></span>
      <span class="nombre">${nombreCorto(p)}</span>
      <span class="monto">${fila ? millones(fila.ventas) : "–"}</span></li>`;
  }).join("");
}

// ---------- KPIs ----------

function dibujarKpis() {
  const v = filaVentas(filtros);
  const u = filaUsuarios(filtros.mes);
  const n = filaNps(filtros.mes, filtros.canal);

  document.getElementById("k-ventas").textContent = v ? millones(v.ventas) : "–";
  document.getElementById("k-ticket").textContent = v ? miles(v.ticket_promedio) : "–";
  document.getElementById("k-usuarios").textContent = u ? milesSinPeso(u.usuarios_activos) : "–";
  document.getElementById("k-nps").textContent = n ? num(n.nps, 1) : "–";

  const notaU = document.getElementById("n-usuarios");
  const otrosU = filtros.canal !== TODOS || filtros.provincia !== TODAS || filtros.producto !== TODOS;
  notaU.textContent = otrosU
    ? "Toda la web: las visitas no tienen canal, provincia ni producto"
    : "Clientes distintos que entraron a la web con su cuenta";
  notaU.classList.toggle("aviso", otrosU);

  const notaN = document.getElementById("n-nps");
  const otrosN = filtros.provincia !== TODAS || filtros.producto !== TODOS;
  notaN.textContent = otrosN
    ? "Sin provincia ni producto: la encuesta no dice qué pedido evalúa"
    : "Promotores menos detractores, de −100 a 100";
  notaN.classList.toggle("aviso", otrosN);

  document.getElementById("c-nps").textContent =
    filtros.canal === TODOS ? "Ambos canales" : filtros.canal;
}

// ---------- Gráficos ----------

const FUENTE = '"Atkinson Hyperlegible", "Segoe UI", system-ui, sans-serif';

function baseOpciones(formato) {
  const tinta = color("--tinta-2");
  const linea = color("--linea");
  Chart.defaults.font.family = FUENTE;
  return {
    locale: "es-AR",
    responsive: true,
    maintainAspectRatio: false,
    animation: { duration: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 450 },
    interaction: { mode: "index", intersect: false },
    plugins: {
      legend: { display: false },
      tooltip: {
        backgroundColor: color("--tinta"),
        titleColor: color("--fondo"),
        bodyColor: color("--fondo"),
        titleFont: { family: FUENTE, weight: "700" },
        bodyFont: { family: FUENTE },
        padding: 10,
        displayColors: false,
        callbacks: { label: (c) => formato(c.parsed.y ?? c.parsed.x) },
      },
    },
    scales: {
      x: {
        grid: { display: false },
        border: { color: linea },
        ticks: { color: tinta, font: { family: FUENTE, size: 12 }, maxRotation: 0, autoSkipPadding: 12 },
      },
      y: {
        grid: { color: linea, drawTicks: false },
        border: { display: false },
        ticks: { color: tinta, font: { family: FUENTE, size: 12 }, padding: 8 },
      },
    },
  };
}

function grafico(id, config) {
  // Si el gráfico ya existe, se actualiza en el lugar (así los cambios de filtro se animan suave).
  const actual = graficos[id];
  if (actual && actual.config.type === config.type) {
    actual.data = config.data;
    actual.options = config.options;
    actual.update();
    return;
  }
  if (actual) actual.destroy();
  graficos[id] = new Chart(document.getElementById(id), config);
}

// Etiqueta del eje en millones: con decimal solo si hace falta (evita "1, 1, 2, 2").
const ejeMillones = (v) => num(v / 1e6, Number.isInteger(v / 1e6) ? 0 : 1);

function resaltar(meses, colorBase) {
  // Con un mes elegido, ese mes queda en color pleno y el resto se atenúa.
  return meses.map((m) => (filtros.mes === TODOS || m === filtros.mes ? colorBase : colorBase + "44"));
}

function dibujarGraficos() {
  const meses = opciones(datos.usuarios, "mes", TODOS);
  const etiquetas = meses.map(mesCorto);
  const serie = color("--serie");

  // Ventas por mes (respeta canal, provincia y producto)
  const ventasMes = meses.map((m) => (filaVentas({ ...filtros, mes: m }) || {}).ventas ?? null);
  const colorVentas = filtros.producto === TODOS ? serie : colorProducto(filtros.producto);
  const opV = baseOpciones((v) => millones(v));
  opV.scales.y.ticks.callback = ejeMillones;
  grafico("g-ventas", {
    type: "bar",
    data: { labels: etiquetas, datasets: [{ data: ventasMes, backgroundColor: resaltar(meses, colorVentas),
      borderRadius: { topLeft: 4, topRight: 4 }, borderSkipped: "bottom", maxBarThickness: 22 }] },
    options: opV,
  });

  // Usuarios activos por mes
  const usuariosMes = meses.map((m) => filaUsuarios(m).usuarios_activos);
  const opU = baseOpciones((v) => `${num(v)} usuarios`);
  grafico("g-usuarios", {
    type: "line",
    data: { labels: etiquetas, datasets: [{ data: usuariosMes, borderColor: serie, borderWidth: 2, cubicInterpolationMode: "monotone",
      pointRadius: meses.map((m) => (m === filtros.mes ? 5 : 0)), pointBackgroundColor: serie,
      pointBorderColor: color("--fondo"), pointBorderWidth: 2, pointHoverRadius: 5 }] },
    options: opU,
  });

  // NPS por mes (respeta canal)
  const npsMes = meses.map((m) => (filaNps(m, filtros.canal) || {}).nps ?? null);
  const opN = baseOpciones((v) => `NPS ${num(v, 1)}`);
  opN.scales.y.suggestedMin = 0;
  grafico("g-nps", {
    type: "line",
    data: { labels: etiquetas, datasets: [{ data: npsMes, borderColor: serie, borderWidth: 2, cubicInterpolationMode: "monotone",
      pointRadius: meses.map((m) => (m === filtros.mes ? 5 : 0)), pointBackgroundColor: serie,
      pointBorderColor: color("--fondo"), pointBorderWidth: 2, pointHoverRadius: 5 }] },
    options: opN,
  });

  // Ventas por provincia (respeta período, canal y producto)
  const provincias = datos.ventas
    .filter((r) => r.mes === filtros.mes && r.canal === filtros.canal && r.producto === filtros.producto && r.provincia !== TODAS)
    .sort((a, b) => b.ventas - a.ventas);
  const colorProv = filtros.producto === TODOS ? serie : colorProducto(filtros.producto);
  const opP = baseOpciones((v) => millones(v));
  opP.indexAxis = "y";
  opP.interaction = { mode: "nearest", axis: "y", intersect: false };
  opP.scales.x.ticks.callback = ejeMillones;
  opP.scales.x.grid = { color: color("--linea"), drawTicks: false };
  opP.scales.y.grid = { display: false };
  grafico("g-provincias", {
    type: "bar",
    data: { labels: provincias.map((r) => r.provincia), datasets: [{ data: provincias.map((r) => r.ventas),
      backgroundColor: provincias.map((r) =>
        filtros.provincia === TODAS || r.provincia === filtros.provincia ? colorProv : colorProv + "44"),
      borderRadius: { topRight: 4, bottomRight: 4 }, borderSkipped: "left", maxBarThickness: 26 }] },
    options: opP,
  });
}

// ---------- Ranking ----------

function dibujarRanking() {
  const filas = datos.ranking
    .filter((r) => r.mes === filtros.mes && r.canal === filtros.canal && r.provincia === filtros.provincia)
    .sort((a, b) => a.puesto - b.puesto);
  const lista = document.getElementById("ranking");
  const lugar = [filtros.mes === TODOS ? "Todo el período" : mesLargo(filtros.mes)];
  if (filtros.canal !== TODOS) lugar.push(filtros.canal);
  if (filtros.provincia !== TODAS) lugar.push(filtros.provincia);
  document.getElementById("c-ranking").textContent = `${lugar.join(", ")}. Por ventas sin IVA`;

  if (!filas.length) {
    lista.innerHTML = `<li class="vacio">Sin ventas con estos filtros</li>`;
    return;
  }
  const mayor = filas[0].ventas_sin_iva;  // escala del dibujo de las barras
  lista.innerHTML = filas.map((r) => `
    <li class="${filtros.producto !== TODOS && r.producto !== filtros.producto ? "apagada" : ""}">
      <span class="puesto">${r.puesto}</span>
      <div>
        <div class="fila">
          <span class="prod">${nombreCorto(r.producto)}</span>
          <span class="cifras">${millones(r.ventas_sin_iva)}, ${num(r.unidades)} unidades</span>
        </div>
        <div class="barra" style="width:${(r.ventas_sin_iva / mayor) * 100}%;background:${colorProducto(r.producto)}"></div>
      </div>
    </li>`).join("");
}

// ---------- Todo junto ----------

function dibujar() {
  marcarSegmentos();
  dibujarTitular();
  dibujarBotella();
  dibujarKpis();
  dibujarGraficos();
  dibujarRanking();
}

cargar()
  .then((d) => {
    datos = d;
    armarFiltros();
    dibujar();
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
      Object.values(graficos).forEach((g) => g.destroy());
      Object.keys(graficos).forEach((k) => delete graficos[k]);
      dibujar();
    });
  })
  .catch((error) => {
    document.getElementById("titular").textContent = "No se pudieron cargar los datos";
    document.getElementById("hero-sub").textContent =
      `${error.message}. Abrí la página desde GitHub Pages o con un servidor local (python -m http.server), no con doble clic.`;
  });
