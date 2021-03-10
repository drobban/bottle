function reloadImage(URL, id) {
    let url = URL  + "#" + new Date().getTime();
    let image = document.getElementById(id);
    var tester=new Image();
    tester.onload= function() {
        imageFound(url, image);
    };
    tester.onerror=imageNotFound;
    tester.src=url;
    setTimeout(function() {reloadImage(URL, id);}, 1000);
}

function imageFound(URL, image) {
    image.src = URL;
    console.log("loaded");
}

function imageNotFound() {
    console.log("error");
}

