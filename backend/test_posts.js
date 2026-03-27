const http = require('http');

async function testPostsApi() {
    console.log('--- Testing Friend Circle Posts API ---');

    let token;
    const ts = Date.now() % 100000;
    const email = 'test_' + ts + '@test.com';
    const username = 'testuser_' + ts;

    try {
        const loginRes = await fetch('http://localhost:5000/api/auth/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ email: 'test@test.com', password: 'password123' })
        });

        const loginData = await loginRes.json();
        if (loginData.token) {
            token = loginData.token;
            console.log('âœ… Login successful');
        } else {
            throw new Error('Login failed');
        }
    } catch (e) {
        console.error('Login failed, creating test user...');
        const createRes = await fetch('http://localhost:5000/api/auth/register', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, email, password: 'password123' })
        });
        const createData = await createRes.json();
        if (!createData.token) {
            console.error('Creation failed. Aborting.', createData);
            return;
        }
        console.log('âœ… Created test user and logged in');
        token = createData.token;
    }

    const headers = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
    };

    // 1. Create Post
    console.log('\n1. Creating Post...');
    const createPostRes = await fetch('http://localhost:5000/api/posts', {
        method: 'POST',
        headers,
        body: JSON.stringify({ content: "Hello world! This is my first test post. @testuser" })
    });
    const post = await createPostRes.json();
    console.log('Post Status:', createPostRes.status);
    console.log('Post:', post);

    if (!post._id) return console.log('Abort: post creation failed');
    const postId = post._id;

    // 2. Get Feed
    console.log('\n2. Getting Feed...');
    const feedRes = await fetch('http://localhost:5000/api/posts/feed', { headers });
    const feed = await feedRes.json();
    console.log('Feed Status:', feedRes.status);
    console.log('Feed posts length:', feed.posts ? feed.posts.length : 0);

    // 3. Like Post
    console.log(`\n3. Liking Post ${postId}...`);
    const likeRes = await fetch(`http://localhost:5000/api/posts/${postId}/like`, { method: 'POST', headers });
    const likeData = await likeRes.json();
    console.log('Like Status:', likeRes.status);
    console.log('Like Data:', likeData);

    // 4. Comment on Post
    console.log(`\n4. Commenting on Post ${postId}...`);
    const commentRes = await fetch(`http://localhost:5000/api/posts/${postId}/comments`, {
        method: 'POST', headers,
        body: JSON.stringify({ content: "Great test post!" })
    });
    const commentData = await commentRes.json();
    console.log('Comment Status:', commentRes.status);
    console.log('Comment Data:', commentData);

    console.log('\nâœ… All Post endpoints tested.');
}

testPostsApi().catch(console.error);






