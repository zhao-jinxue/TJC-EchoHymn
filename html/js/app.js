/* ===== EchoHymn 主应用逻辑 ===== */
(function () {
    "use strict";

    // ---- DOM 引用 ----
    const hymnListEl = document.getElementById("hymnList");
    const hymnCountEl = document.getElementById("hymnCount");
    const searchInput = document.getElementById("searchInput");
    const lyricsEl = document.getElementById("lyrics");
    const lyricsEmptyEl = document.getElementById("lyricsEmpty");

    const playerEmpty = document.getElementById("playerEmpty");
    const playerActive = document.getElementById("playerActive");
    const songTitleEl = document.getElementById("songTitle");
    const songMetaEl = document.getElementById("songMeta");
    const playBtn = document.getElementById("playBtn");
    const prevBtn = document.getElementById("prevBtn");
    const nextBtn = document.getElementById("nextBtn");
    const progressBar = document.getElementById("progressBar");
    const currentTimeEl = document.getElementById("currentTime");
    const durationEl = document.getElementById("duration");
    const volumeBar = document.getElementById("volumeBar");

    const sidebar = document.getElementById("sidebar");
    const overlay = document.getElementById("overlay");
    const menuBtn = document.getElementById("menuBtn");
    const sidebarToggle = document.getElementById("sidebarToggle");

    // ---- 播放器 ----
    const audio = new Audio();
    let currentIndex = -1;
    let isPlaying = false;

    // ---- 工具函数 ----
    function formatTime(sec) {
        if (!isFinite(sec) || sec < 0) return "0:00";
        const m = Math.floor(sec / 60);
        const s = Math.floor(sec % 60);
        return m + ":" + (s < 10 ? "0" + s : s);
    }

    // ---- 渲染诗歌列表 ----
    function renderHymnList(filterText) {
        const keyword = (filterText || "").trim().toLowerCase();
        const filtered = HYMNS.filter(function (h) {
            if (!keyword) return true;
            return (
                String(h.number).indexOf(keyword) !== -1 ||
                h.title.toLowerCase().indexOf(keyword) !== -1 ||
                h.author.toLowerCase().indexOf(keyword) !== -1 ||
                h.category.toLowerCase().indexOf(keyword) !== -1
            );
        });

        hymnListEl.innerHTML = "";
        filtered.forEach(function (h) {
            const li = document.createElement("li");
            li.className = "hymn-item";
            if (h.id === HYMNS[currentIndex].id) {
                li.classList.add("active");
            }
            li.dataset.id = h.id;

            const numSpan = document.createElement("span");
            numSpan.className = "hymn-num";
            numSpan.textContent = String(h.number).padStart(3, "0");

            const nameSpan = document.createElement("span");
            nameSpan.className = "hymn-name";
            nameSpan.textContent = h.title;

            li.appendChild(numSpan);
            li.appendChild(nameSpan);

            li.addEventListener("click", function () {
                const idx = HYMNS.findIndex(function (x) { return x.id === h.id; });
                if (idx !== -1) {
                    playHymn(idx);
                    closeSidebar();
                }
            });

            hymnListEl.appendChild(li);
        });

        hymnCountEl.textContent = filtered.length;
    }

    // ---- 渲染歌词 ----
    function renderLyrics(hymn) {
        lyricsEmptyEl.classList.add("hidden");
        lyricsEl.innerHTML = "";

        hymn.lyrics.forEach(function (stanza) {
            const stanzaDiv = document.createElement("div");
            stanzaDiv.className = "lyric-stanza";
            stanza.forEach(function (line) {
                const p = document.createElement("p");
                p.className = "lyric-line";
                p.textContent = line;
                stanzaDiv.appendChild(p);
            });
            lyricsEl.appendChild(stanzaDiv);
        });
    }

    // ---- 播放控制 ----
    function playHymn(index) {
        if (index < 0 || index >= HYMNS.length) return;
        currentIndex = index;
        const hymn = HYMNS[index];

        // 标题 / 元信息
        songTitleEl.textContent = hymn.title;
        songMetaEl.textContent =
            "第 " + hymn.number + " 首 · " + hymn.category +
            " · 词：" + hymn.author + " · 曲：" + hymn.composer;

        // 切换界面
        playerEmpty.classList.add("hidden");
        playerActive.classList.remove("hidden");

        // 歌词
        renderLyrics(hymn);

        // 音频
        audio.src = hymn.audio;
        audio.currentTime = 0;
        audio.play().then(function () {
            isPlaying = true;
            playBtn.textContent = "⏸";
        }).catch(function () {
            isPlaying = false;
            playBtn.textContent = "▶";
            // 音频加载失败时提示（例如网络受限）
            songMetaEl.textContent += "（音频加载失败）";
        });

        // 列表高亮
        const items = hymnListEl.querySelectorAll(".hymn-item");
        items.forEach(function (item) {
            item.classList.toggle("active", Number(item.dataset.id) === hymn.id);
        });
    }

    function togglePlay() {
        if (currentIndex === -1) {
            if (HYMNS.length > 0) {
                playHymn(0);
            }
            return;
        }
        if (audio.paused) {
            audio.play().catch(function () { });
            playBtn.textContent = "⏸";
        } else {
            audio.pause();
            playBtn.textContent = "▶";
        }
    }

    function playNext() {
        if (HYMNS.length === 0) return;
        const next = currentIndex === -1 ? 0 : (currentIndex + 1) % HYMNS.length;
        playHymn(next);
    }

    function playPrev() {
        if (HYMNS.length === 0) return;
        let prev = currentIndex === -1 ? 0 : (currentIndex - 1 + HYMNS.length) % HYMNS.length;
        playHymn(prev);
    }

    // ---- 事件绑定 ----
    playBtn.addEventListener("click", togglePlay);
    nextBtn.addEventListener("click", playNext);
    prevBtn.addEventListener("click", playPrev);

    audio.addEventListener("timeupdate", function () {
        if (isFinite(audio.duration)) {
            progressBar.max = audio.duration;
        }
        progressBar.value = audio.currentTime;
        currentTimeEl.textContent = formatTime(audio.currentTime);
        durationEl.textContent = formatTime(audio.duration);
    });

    audio.addEventListener("loadedmetadata", function () {
        progressBar.max = audio.duration;
        durationEl.textContent = formatTime(audio.duration);
    });

    audio.addEventListener("ended", playNext);

    progressBar.addEventListener("input", function () {
        if (isFinite(audio.duration)) {
            audio.currentTime = Number(progressBar.value);
        }
    });

    volumeBar.addEventListener("input", function () {
        audio.volume = Number(volumeBar.value);
    });
    audio.volume = 0.8;

    // 搜索
    searchInput.addEventListener("input", function () {
        renderHymnList(this.value);
    });

    // 侧边栏（移动端）
    menuBtn.addEventListener("click", function () {
        sidebar.classList.add("open");
        overlay.classList.remove("hidden");
    });

    sidebarToggle.addEventListener("click", closeSidebar);
    overlay.addEventListener("click", closeSidebar);

    function closeSidebar() {
        sidebar.classList.remove("open");
        overlay.classList.add("hidden");
    }

    // 键盘快捷方式
    document.addEventListener("keydown", function (e) {
        // 输入框内不响应快捷键
        if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA") return;
        if (e.code === "Space") {
            e.preventDefault();
            togglePlay();
        } else if (e.code === "ArrowRight") {
            playNext();
        } else if (e.code === "ArrowLeft") {
            playPrev();
        }
    });

    // ---- 初始化 ----
    renderHymnList("");
    hymnCountEl.textContent = HYMNS.length;
})();
