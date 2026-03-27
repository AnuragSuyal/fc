// Initial gift catalog - 50+ gifts across 4 tiers
const giftCatalog = [
    // TIER 1: SIMPLE GIFTS (50-500 coins)
    {
        name: 'Heart',
        description: 'Show someone you care',
        icon: 'â¤ï¸',
        price: { coins: 50, gems: 0 },
        category: 'simple',
        tier: 1,
        animation: {
            type: 'float',
            duration: 3,
            color: '#FF3B30',
            particleCount: 20
        },
        effects: {
            sender: { xp: 5 },
            recipient: { effect: 'heart_float', duration: 3 }
        }
    },
    {
        name: 'Rose',
        description: 'A classic symbol of love',
        icon: 'ðŸŒ¹',
        price: { coins: 100, gems: 0 },
        category: 'simple',
        tier: 1,
        animation: {
            type: 'float',
            duration: 4,
            color: '#FF69B4',
            particleCount: 30
        },
        effects: {
            sender: { xp: 8 },
            recipient: { effect: 'rose_bloom', duration: 4 }
        }
    },
    {
        name: 'Clap',
        description: 'Give them a round of applause',
        icon: 'ðŸ‘',
        price: { coins: 150, gems: 0 },
        category: 'simple',
        tier: 1,
        animation: {
            type: 'explode',
            duration: 2,
            color: '#FFD700',
            particleCount: 40
        },
        effects: {
            sender: { xp: 10 }
        }
    },
    {
        name: 'Smile',
        description: 'Spread some happiness',
        icon: 'ðŸ˜Š',
        price: { coins: 200, gems: 0 },
        category: 'simple',
        tier: 1,
        animation: {
            type: 'float',
            duration: 3,
            color: '#FFA500',
            particleCount: 25
        },
        effects: {
            sender: { xp: 12 }
        }
    },
    {
        name: 'Thumbs Up',
        description: 'Show your approval',
        icon: 'ðŸ‘',
        price: { coins: 250, gems: 0 },
        category: 'simple',
        tier: 1,
        animation: {
            type: 'fly',
            duration: 2,
            color: '#4CAF50'
        },
        effects: {
            sender: { xp: 15 }
        }
    },
    {
        name: 'Wave',
        description: 'Say hello in style',
        icon: 'ðŸ‘‹',
        price: { coins: 300, gems: 0 },
        category: 'simple',
        tier: 1,
        animation: {
            type: 'fly',
            duration: 3,
            color: '#2196F3'
        },
        effects: {
            sender: { xp: 18 }
        }
    },
    {
        name: 'Star',
        description: "You're a star!",
        icon: 'â­',
        price: { coins: 400, gems: 0 },
        category: 'simple',
        tier: 1,
        animation: {
            type: 'explode',
            duration: 3,
            color: '#FFD700',
            particleCount: 60
        },
        effects: {
            sender: { xp: 20 },
            recipient: { effect: 'twinkle', duration: 5 }
        }
    },
    {
        name: 'Fire',
        description: "You're on fire!",
        icon: 'ðŸ”¥',
        price: { coins: 500, gems: 0 },
        category: 'simple',
        tier: 1,
        animation: {
            type: 'explode',
            duration: 4,
            color: '#FF4500',
            particleCount: 80
        },
        effects: {
            sender: { xp: 25 },
            recipient: { effect: 'burning', duration: 5 }
        }
    },
    {
        name: 'Coffee',
        description: 'Keep the energy up',
        icon: 'â˜•',
        price: { coins: 60, gems: 0 },
        category: 'simple',
        tier: 1,
        animation: { type: 'float', duration: 2, color: '#6F4E37' },
        effects: { sender: { xp: 5 } }
    },
    {
        name: 'Beer',
        description: 'Cheers!',
        icon: 'ðŸº',
        price: { coins: 80, gems: 0 },
        category: 'simple',
        tier: 1,
        animation: { type: 'explode', duration: 2, color: '#FFD700' },
        effects: { sender: { xp: 6 } }
    },
    {
        name: 'Cake',
        description: 'Sweet treat',
        icon: 'ðŸ°',
        price: { coins: 120, gems: 0 },
        category: 'simple',
        tier: 1,
        animation: { type: 'float', duration: 3, color: '#FF69B4' },
        effects: { sender: { xp: 8 } }
    },
    {
        name: 'Balloon',
        description: 'Party time!',
        icon: 'ðŸŽˆ',
        price: { coins: 150, gems: 0 },
        category: 'simple',
        tier: 1,
        animation: { type: 'float', duration: 5, color: '#FF0000' },
        effects: { sender: { xp: 10 } }
    },
    {
        name: 'Pizza',
        description: 'Delicious pizza slice',
        icon: 'ðŸ•',
        price: { coins: 180, gems: 0 },
        category: 'simple',
        tier: 1,
        animation: { type: 'float', duration: 3, color: '#FFA500' },
        effects: { sender: { xp: 12 } }
    },
    {
        name: 'Ice Cream',
        description: 'Cool down',
        icon: 'ðŸ¦',
        price: { coins: 200, gems: 0 },
        category: 'simple',
        tier: 1,
        animation: { type: 'float', duration: 3, color: '#FFFFFF' },
        effects: { sender: { xp: 14 } }
    },
    {
        name: 'Sunglasses',
        description: 'Looking cool',
        icon: 'ðŸ˜Ž',
        price: { coins: 220, gems: 0 },
        category: 'simple',
        tier: 1,
        animation: { type: 'fly', duration: 2, color: '#000000' },
        effects: { sender: { xp: 15 } }
    },
    {
        name: 'Camera',
        description: 'Capture the moment',
        icon: 'ðŸ“¸',
        price: { coins: 250, gems: 0 },
        category: 'simple',
        tier: 1,
        animation: { type: 'explode', duration: 1, color: '#FFFFFF' },
        effects: { sender: { xp: 18 } }
    },
    {
        name: 'Gift Box',
        description: 'A surprise inside',
        icon: 'ðŸŽ',
        price: { coins: 300, gems: 0 },
        category: 'simple',
        tier: 1,
        animation: { type: 'explode', duration: 3, color: '#FF0000' },
        effects: { sender: { xp: 20 } }
    },
    {
        name: 'Microphone',
        description: 'You have a great voice',
        icon: 'ðŸŽ¤',
        price: { coins: 350, gems: 0 },
        category: 'simple',
        tier: 1,
        animation: { type: 'float', duration: 4, color: '#C0C0C0' },
        effects: { sender: { xp: 22 } }
    },

    // TIER 2: PREMIUM GIFTS (600-2,500 coins)
    {
        name: 'Crown',
        description: 'Treat them like royalty',
        icon: 'ðŸ‘‘',
        price: { coins: 600, gems: 0 },
        category: 'premium',
        tier: 2,
        animation: {
            type: 'screen',
            duration: 4,
            color: '#FFD700',
            particleCount: 100
        },
        effects: {
            sender: { xp: 30, badge: 'RoyalGiver' },
            recipient: { effect: 'crown_wear', duration: 10 }
        }
    },
    {
        name: 'Trophy',
        description: 'Celebrate their victory',
        icon: 'ðŸ†',
        price: { coins: 800, gems: 0 },
        category: 'premium',
        tier: 2,
        animation: {
            type: 'screen',
            duration: 5,
            color: '#FFD700',
            particleCount: 120
        },
        effects: {
            sender: { xp: 35 },
            recipient: { effect: 'trophy_shine', duration: 8 }
        }
    },
    {
        name: 'Diamond',
        description: 'A precious gift',
        icon: 'ðŸ’Ž',
        price: { coins: 1000, gems: 0 },
        category: 'premium',
        tier: 2,
        animation: {
            type: 'explode',
            duration: 5,
            color: '#00FFFF',
            particleCount: 150
        },
        effects: {
            sender: { xp: 40, badge: 'DiamondHands' },
            recipient: { effect: 'diamond_shine', duration: 10 }
        }
    },
    {
        name: 'Rocket',
        description: 'Send them to the moon',
        icon: 'ðŸš€',
        price: { coins: 1200, gems: 0 },
        category: 'premium',
        tier: 2,
        animation: {
            type: 'fly',
            duration: 5,
            color: '#FF5722',
            particleCount: 100
        },
        effects: {
            sender: { xp: 45 },
            room: { background: 'space', duration: 15 }
        }
    },
    {
        name: 'Unicorn',
        description: 'Magical and rare',
        icon: 'ðŸ¦„',
        price: { coins: 1500, gems: 0 },
        category: 'premium',
        tier: 2,
        animation: {
            type: 'fly',
            duration: 6,
            color: '#FF69B4',
            particleCount: 120
        },
        effects: {
            sender: { xp: 50 },
            room: { background: 'rainbow', duration: 20 }
        }
    },
    {
        name: 'Dragon',
        description: 'Unleash the beast',
        icon: 'ðŸ‰',
        price: { coins: 2000, gems: 0 },
        category: 'premium',
        tier: 2,
        animation: {
            type: 'screen',
            duration: 6,
            color: '#FF4500',
            particleCount: 200
        },
        effects: {
            sender: { xp: 60, badge: 'DragonSlayer' },
            room: { background: 'fire', duration: 20 }
        }
    },
    {
        name: 'Phoenix',
        description: 'Rise from the ashes',
        icon: 'ðŸ”¥ðŸ¦',
        price: { coins: 2500, gems: 0 },
        category: 'premium',
        tier: 2,
        animation: {
            type: 'screen',
            duration: 7,
            color: '#FF6347',
            particleCount: 250
        },
        effects: {
            sender: { xp: 70 },
            recipient: { effect: 'rebirth', duration: 15 }
        }
    },
    {
        name: 'Magic Wand',
        description: 'Make a wish',
        icon: 'ðŸª„',
        price: { coins: 650, gems: 0 },
        category: 'premium',
        tier: 2,
        animation: { type: 'screen', duration: 4, color: '#FFD700' },
        effects: { sender: { xp: 32 } }
    },
    {
        name: 'Treasure Chest',
        description: 'Full of gold',
        icon: 'ðŸ’°',
        price: { coins: 750, gems: 0 },
        category: 'premium',
        tier: 2,
        animation: { type: 'explode', duration: 5, color: '#FFD700' },
        effects: { sender: { xp: 35 } }
    },
    {
        name: 'Flying Plane',
        description: 'Up in the sky',
        icon: 'ðŸ›©ï¸',
        price: { coins: 900, gems: 0 },
        category: 'premium',
        tier: 2,
        animation: { type: 'fly', duration: 5, color: '#FFFFFF' },
        effects: { sender: { xp: 38 } }
    },
    {
        name: 'Gold Medal',
        description: 'You are #1',
        icon: 'ðŸ¥‡',
        price: { coins: 1100, gems: 0 },
        category: 'premium',
        tier: 2,
        animation: { type: 'screen', duration: 4, color: '#FFD700' },
        effects: { sender: { xp: 42 } }
    },
    {
        name: 'Violin',
        description: 'Beautiful melody',
        icon: 'ðŸŽ»',
        price: { coins: 1300, gems: 0 },
        category: 'premium',
        tier: 2,
        animation: { type: 'float', duration: 6, color: '#8B4513' },
        effects: { sender: { xp: 48 } }
    },
    {
        name: 'Red Carpet',
        description: 'VIP treatment',
        icon: 'ðŸ®',
        price: { coins: 1600, gems: 0 },
        category: 'premium',
        tier: 2,
        animation: { type: 'screen', duration: 5, color: '#FF0000' },
        effects: { sender: { xp: 55 } }
    },
    {
        name: 'Statue of Liberty',
        description: 'Symbol of freedom',
        icon: 'ðŸ—½',
        price: { coins: 1800, gems: 0 },
        category: 'premium',
        tier: 2,
        animation: { type: 'float', duration: 6, color: '#40E0D0' },
        effects: { sender: { xp: 58 } }
    },
    {
        name: 'Eiffel Tower',
        description: 'Romantic Paris',
        icon: 'ðŸ—¼',
        price: { coins: 2100, gems: 0 },
        category: 'premium',
        tier: 2,
        animation: { type: 'float', duration: 7, color: '#A9A9A9' },
        effects: { sender: { xp: 65 } }
    },
    {
        name: 'Golden Dragon',
        description: 'Divine creature',
        icon: 'ðŸ²',
        price: { coins: 2400, gems: 0 },
        category: 'premium',
        tier: 2,
        animation: { type: 'screen', duration: 8, color: '#FFD700' },
        effects: { sender: { xp: 75 } }
    },
    {
        name: 'Majestic Griffin',
        description: 'Guardian of riches',
        icon: 'ðŸ¦…',
        price: { coins: 2800, gems: 0 },
        category: 'premium',
        tier: 2,
        animation: { type: 'fly', duration: 7, color: '#DAA520' },
        effects: { sender: { xp: 85 } }
    },

    // TIER 3: LUXURY GIFTS (50-500 gems)
    {
        name: 'Luxury Car',
        description: 'Ride in style',
        icon: 'ðŸŽï¸',
        price: { coins: 0, gems: 50 },
        category: 'luxury',
        tier: 3,
        animation: {
            type: 'fly',
            duration: 6,
            color: '#FF0000',
            particleCount: 150
        },
        effects: {
            sender: { xp: 100, badge: 'HighRoller' },
            recipient: { effect: 'car_drive', duration: 15 },
            room: { background: 'racetrack', duration: 20 }
        }
    },
    {
        name: 'Yacht',
        description: 'Sail away',
        icon: 'â›µ',
        price: { coins: 0, gems: 100 },
        category: 'luxury',
        tier: 3,
        animation: {
            type: 'float',
            duration: 7,
            color: '#00BFFF',
            particleCount: 180
        },
        effects: {
            sender: { xp: 150 },
            room: { background: 'ocean', duration: 25 }
        }
    },
    {
        name: 'Private Jet',
        description: 'Travel in luxury',
        icon: 'âœˆï¸',
        price: { coins: 0, gems: 200 },
        category: 'luxury',
        tier: 3,
        animation: {
            type: 'fly',
            duration: 8,
            color: '#FFFFFF',
            particleCount: 200
        },
        effects: {
            sender: { xp: 200, badge: 'JetSetter' },
            room: { background: 'clouds', duration: 30 }
        }
    },
    {
        name: 'Castle',
        description: 'Live like royalty',
        icon: 'ðŸ°',
        price: { coins: 0, gems: 300 },
        category: 'luxury',
        tier: 3,
        animation: {
            type: 'screen',
            duration: 8,
            color: '#9370DB',
            particleCount: 250
        },
        effects: {
            sender: { xp: 250 },
            room: { background: 'castle', duration: 35 }
        }
    },
    {
        name: 'Galaxy',
        description: 'Explore the universe',
        icon: 'ðŸŒŒ',
        price: { coins: 0, gems: 400 },
        category: 'luxury',
        tier: 3,
        animation: {
            type: 'screen',
            duration: 9,
            color: '#4B0082',
            particleCount: 300
        },
        effects: {
            sender: { xp: 300, badge: 'Stargazer' },
            room: { background: 'galaxy', duration: 40 }
        }
    },
    {
        name: 'Universe',
        description: 'The ultimate gift',
        icon: 'ðŸŒ ',
        price: { coins: 0, gems: 500 },
        category: 'luxury',
        tier: 3,
        animation: {
            type: 'screen',
            duration: 10,
            color: '#000000',
            particleCount: 500
        },
        effects: {
            sender: { xp: 400, badge: 'Cosmic' },
            room: { background: 'universe', duration: 50 }
        }
    },
    {
        name: 'Diamond Ring',
        description: 'Eternal value',
        icon: 'ðŸ’',
        price: { coins: 0, gems: 60 },
        category: 'luxury',
        tier: 3,
        animation: { type: 'explode', duration: 5, color: '#B0E0E6' },
        effects: { sender: { xp: 110 } }
    },
    {
        name: 'Luxury Watch',
        description: 'Timeless elegance',
        icon: 'âŒš',
        price: { coins: 0, gems: 80 },
        category: 'luxury',
        tier: 3,
        animation: { type: 'float', duration: 6, color: '#C0C0C0' },
        effects: { sender: { xp: 130 } }
    },
    {
        name: 'Mansion',
        description: 'Luxury living',
        icon: 'ðŸ¡',
        price: { coins: 0, gems: 150 },
        category: 'luxury',
        tier: 3,
        animation: { type: 'screen', duration: 7, color: '#F5F5DC' },
        effects: { sender: { xp: 180 } }
    },
    {
        name: 'Island',
        description: 'Your own paradise',
        icon: 'ðŸï¸',
        price: { coins: 0, gems: 250 },
        category: 'luxury',
        tier: 3,
        animation: { type: 'screen', duration: 8, color: '#40E0D0' },
        effects: { sender: { xp: 220 } }
    },
    {
        name: 'Cruise Ship',
        description: 'World tour',
        icon: 'ðŸ›³ï¸',
        price: { coins: 0, gems: 350 },
        category: 'luxury',
        tier: 3,
        animation: { type: 'float', duration: 9, color: '#FFFFFF' },
        effects: { sender: { xp: 280 } }
    },
    {
        name: 'Golden Gate',
        description: 'Iconic bridge',
        icon: 'ðŸŒ‰',
        price: { coins: 0, gems: 450 },
        category: 'luxury',
        tier: 3,
        animation: { type: 'screen', duration: 10, color: '#FF4500' },
        effects: { sender: { xp: 350 } }
    },
    {
        name: 'Black Hole',
        description: 'Infinite attraction',
        icon: 'ðŸ•³ï¸',
        price: { coins: 0, gems: 600 },
        category: 'luxury',
        tier: 3,
        animation: { type: 'screen', duration: 12, color: '#000000' },
        effects: { sender: { xp: 500 } }
    },
    {
        name: 'Supernova',
        description: 'Stellar explosion',
        icon: 'ðŸ’¥',
        price: { coins: 0, gems: 800 },
        category: 'luxury',
        tier: 3,
        animation: { type: 'screen', duration: 15, color: '#FFD700' },
        effects: { sender: { xp: 700 } }
    },
    {
        name: 'Time Machine',
        description: 'Back to the future',
        icon: 'âŒ›',
        price: { coins: 0, gems: 1200 },
        category: 'luxury',
        tier: 3,
        animation: { type: 'screen', duration: 20, color: '#00FFFF' },
        effects: { sender: { xp: 1000 } }
    },
    {
        name: 'Multiverse',
        description: 'Everything, everywhere',
        icon: 'ðŸª',
        price: { coins: 0, gems: 2000 },
        category: 'luxury',
        tier: 3,
        animation: { type: 'screen', duration: 30, color: '#8A2BE2' },
        effects: { sender: { xp: 2000 } }
    },

    // TIER 4: LEGENDARY GIFTS (Limited Edition)
    {
        name: 'Season 1',
        description: 'Limited edition season 1 gift',
        icon: 'ðŸ…',
        price: { coins: 0, gems: 1000 },
        category: 'legendary',
        tier: 4,
        availability: {
            limited: true,
            totalAvailable: 1000,
            startDate: new Date('2024-01-01'),
            endDate: new Date('2027-12-31')
        },
        animation: {
            type: 'screen',
            duration: 10,
            color: '#FFD700',
            particleCount: 500
        },
        effects: {
            sender: { xp: 1000, badge: 'Legendary' },
            recipient: { effect: 'legendary_glow', duration: 60 }
        }
    },
    {
        name: 'Valentine',
        description: "Special Valentine's gift",
        icon: 'ðŸ’˜',
        price: { coins: 0, gems: 500 },
        category: 'legendary',
        tier: 4,
        availability: {
            limited: true,
            totalAvailable: 5000,
            startDate: new Date(new Date().getFullYear(), 1, 1),
            endDate: new Date(new Date().getFullYear(), 1, 14)
        },
        animation: {
            type: 'screen',
            duration: 8,
            color: '#FF1493',
            particleCount: 400
        },
        effects: {
            sender: { xp: 500, badge: 'Cupid' },
            recipient: { effect: 'hearts', duration: 30 }
        }
    },
    {
        name: 'Halloween',
        description: 'Spooky Halloween special',
        icon: 'ðŸŽƒ',
        price: { coins: 0, gems: 500 },
        category: 'legendary',
        tier: 4,
        availability: {
            limited: true,
            totalAvailable: 5000,
            startDate: new Date(new Date().getFullYear(), 9, 1),
            endDate: new Date(new Date().getFullYear(), 9, 31)
        },
        animation: {
            type: 'screen',
            duration: 8,
            color: '#FF4500',
            particleCount: 400
        },
        effects: {
            sender: { xp: 500, badge: 'Spooky' },
            room: { background: 'halloween', duration: 30 }
        }
    },
    {
        name: 'Christmas',
        description: 'Merry Christmas!',
        icon: 'ðŸŽ„',
        price: { coins: 0, gems: 500 },
        category: 'legendary',
        tier: 4,
        availability: {
            limited: true,
            totalAvailable: 5000,
            startDate: new Date(new Date().getFullYear(), 11, 1),
            endDate: new Date(new Date().getFullYear(), 11, 25)
        },
        animation: {
            type: 'screen',
            duration: 8,
            color: '#FF0000',
            particleCount: 400
        },
        effects: {
            sender: { xp: 500, badge: 'Santa' },
            room: { background: 'christmas', duration: 30 }
        }
    },
    {
        name: 'Founder',
        description: 'Only for the founders',
        icon: 'ðŸŽ–ï¸',
        price: { coins: 0, gems: 5000 },
        category: 'legendary',
        tier: 4,
        availability: { limited: true, totalAvailable: 100 },
        animation: { type: 'screen', duration: 30, color: '#FFD700' },
        effects: { sender: { xp: 10000, badge: 'Founder' } }
    },
    {
        name: 'Golden Idol',
        description: 'A worshiped relic',
        icon: 'ðŸ—¿',
        price: { coins: 0, gems: 2500 },
        category: 'legendary',
        tier: 4,
        availability: { limited: true, totalAvailable: 500 },
        animation: { type: 'screen', duration: 20, color: '#DAA520' },
        effects: { sender: { xp: 5000 } }
    },
    {
        name: 'Phoenix Egg',
        description: 'Wait for the hatching',
        icon: 'ðŸ¥š',
        price: { coins: 0, gems: 1500 },
        category: 'legendary',
        tier: 4,
        availability: { limited: true, totalAvailable: 1000 },
        animation: { type: 'float', duration: 15, color: '#FF8C00' },
        effects: { sender: { xp: 3000 } }
    }
];

module.exports = giftCatalog;






