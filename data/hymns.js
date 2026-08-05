/* EchoHymn 诗歌数据
 * audio: 音频 URL。演示使用公有领域的古典圣乐编曲资源。
 */
const HYMNS = [
    {
        id: 1,
        number: 1,
        title: "天父世界真美丽",
        author: "Maltbie D. Babcock",
        composer: "Franklin L. Sheppard",
        category: "赞美",
        audio: "https://cdn.pixabay.com/download/audio/2022/03/15/audio_4415fbf4a7.mp3?filename=calm-strings-154451.mp3",
        lyrics: [
            [
                "这是天父世界，",
                "我们侧耳要听，",
                "宇宙唱歌四围应和，",
                "星辰作乐同声。"
            ],
            [
                "这是天父世界，",
                "我心满有安宁；",
                "树木花草，苍天碧海，",
                "述说天父全能。"
            ],
            [
                "这是天父世界，",
                "小鸟长翅飞鸣；",
                "清晨明亮好花美丽，",
                "证明天理精深。"
            ]
        ]
    },
    {
        id: 2,
        number: 2,
        title: "你真伟大",
        author: "Carl Boberg",
        composer: "瑞典传统曲调",
        category: "赞美",
        audio: "https://cdn.pixabay.com/download/audio/2022/01/18/audio_d0c6ff1d3d.mp3?filename=emotional-piano-15466.mp3",
        lyrics: [
            [
                "主啊我神！我每逢举目观看，",
                "你手所造一切奇妙大工，",
                "看见星宿，又听到隆隆雷声，",
                "你的大能遍满了宇宙中。"
            ],
            [
                "当我想到，神竟愿差他儿子，",
                "降世舍命，我几乎不领会；",
                "主在十架，甘愿背负我的罪，",
                "流尽宝血，使我得着赦免。"
            ],
            [
                "当主再来，欢呼声响彻天空，",
                "何等喜乐，主接我回天家；",
                "我要跪下，谦恭的崇拜敬奉，",
                "并要颂扬，神啊你真伟大。"
            ]
        ]
    },
    {
        id: 3,
        number: 3,
        title: "奇异恩典",
        author: "John Newton",
        composer: "英文传统曲调",
        category: "恩典",
        audio: "https://cdn.pixabay.com/download/audio/2022/03/07/audio_c8c8a73467.mp3?filename=celtic-music-109346.mp3",
        lyrics: [
            [
                "奇异恩典，何等甘甜，",
                "我罪已得赦免；",
                "前我失丧，今被寻回，",
                "瞎眼今得看见。"
            ],
            [
                "如此恩典，使我敬畏，",
                "使我心得安慰；",
                "初信之时，即蒙恩惠，",
                "真是何等宝贵。"
            ],
            [
                "许多危险，试炼网罗，",
                "我已安然经过；",
                "靠主恩典，安全不怕，",
                "更引导我归家。"
            ]
        ]
    },
    {
        id: 4,
        number: 4,
        title: "轻轻听",
        author: "传统赞美诗",
        composer: "传统赞美诗",
        category: "敬拜",
        audio: "https://cdn.pixabay.com/download/audio/2022/01/18/audio_d0c6ff1d3d.mp3?filename=emotional-piano-15466.mp3",
        lyrics: [
            [
                "轻轻听，我要轻轻听，",
                "我要侧耳听我主声音。",
                "轻轻听，他在轻轻听，",
                "我的牧人认得我声音。"
            ],
            [
                "你是大牧者，生命的主宰，",
                "我一生只听随主声音。",
                "你是大牧者，生命的主宰，",
                "我的牧人认得我声音。"
            ]
        ]
    },
    {
        id: 5,
        number: 5,
        title: "我的救主",
        author: "传统赞美诗",
        composer: "传统赞美诗",
        category: "救赎",
        audio: "https://cdn.pixabay.com/download/audio/2022/03/15/audio_4415fbf4a7.mp3?filename=calm-strings-154451.mp3",
        lyrics: [
            [
                "我的救主，你为我舍命，",
                "在十字架上，流尽宝血；",
                "我的救主，你为我复活，",
                "赐给我新生，盼望无限。"
            ],
            [
                "何等奇妙，何等荣耀，",
                "我愿一生，跟随你到底；",
                "何等恩典，何等慈爱，",
                "我要歌颂，直到永远。"
            ]
        ]
    },
    {
        id: 6,
        number: 6,
        title: "荣耀归于真神",
        author: "Fanny J. Crosby",
        composer: "William H. Doane",
        category: "荣耀",
        audio: "https://cdn.pixabay.com/download/audio/2022/01/18/audio_d0c6ff1d3d.mp3?filename=emotional-piano-15466.mp3",
        lyrics: [
            [
                "赞美真神，万福之源，",
                "天上地下都当称颂；",
                "他赐恩典，他施怜悯，",
                "也以慈爱护佑万民。"
            ],
            [
                "荣耀归于真神，",
                "荣耀归于至高神，",
                "从今直到永远，",
                "赞美他的圣名。"
            ]
        ]
    },
    {
        id: 7,
        number: 7,
        title: "安静认识神",
        author: "传统赞美诗",
        composer: "传统赞美诗",
        category: "灵修",
        audio: "https://cdn.pixabay.com/download/audio/2022/03/07/audio_c8c8a73467.mp3?filename=celtic-music-109346.mp3",
        lyrics: [
            [
                "你们要安静，要知道我是神，",
                "我必在列国中被尊崇。",
                "你们要安静，要知道我是神，",
                "我必在全地被高举。"
            ],
            [
                "主啊我安静，等候你的指引，",
                "我深知你必引导我前行；",
                "主啊我安静，聆听你的微声，",
                "我的盼望单单在于你。"
            ]
        ]
    },
    {
        id: 8,
        number: 8,
        title: "主是坚固磐石",
        author: "传统赞美诗",
        composer: "传统赞美诗",
        category: "信心",
        audio: "https://cdn.pixabay.com/download/audio/2022/03/15/audio_4415fbf4a7.mp3?filename=calm-strings-154451.mp3",
        lyrics: [
            [
                "我的灵啊，你当赞美主，",
                "他是我坚固磐石，避难所；",
                "风浪虽大，我不惧怕，",
                "因有耶稣在我身旁。"
            ],
            [
                "主是磐石，永不摇动，",
                "他的应许坚立到永远；",
                "我要依靠，我要仰望，",
                "一生一世住在主里面。"
            ]
        ]
    }
];
