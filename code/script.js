function sayThankYou() {
    const name = document.getElementById('name').value;
    const thankYouMessage = document.getElementById('thankYouMessage');

    if (name.trim() !== '') {
        thankYouMessage.textContent = `Thank you, ${name}!`;
    } else {
        alert('Please enter your name.');
    }
}
