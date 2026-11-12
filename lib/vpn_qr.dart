// QR codes for Settings > VPN, made ahead of time (tools: segno) so Foyer needs no QR library.
// Each opens that VPN's sign-in or account page on your phone.
import 'dart:convert';
import 'dart:typed_data';

class VpnInfo {
  const VpnInfo(this.name, this.package, this.url, this.blurb, this.qr);
  final String name;
  final String package;
  final String url;
  final String blurb;
  final String qr; // PNG, base64
  Uint8List get qrPng => base64Decode(qr);
}

const List<VpnInfo> kVpns = [
  VpnInfo('NordVPN', 'com.nordvpn.android', 'https://my.nordaccount.com/', 'Popular and fast. Sign in with your Nord Account.',
      'iVBORw0KGgoAAAANSUhEUgAAARgAAAEYAQAAAACv9dQhAAABKklEQVR42u2awQ7CQAhEif//z5haZgB7aGLiRd82se3KxckwA6yR9yuIIYaYj2PiXMf9eMnzSbuZj7hfvxoTxjHqKpi8Cz7Flxd3zo9oFoHPwCfXHXyu+KSJBD7v+lOwWIvQn8JH/rUv/Kt+f5u9BHpXBn+PTwgcGbshgj9NnJD25NBt+JNSm66oVQHVHvnViXaSSPqM/gz/6uo5/UB+tWHFak1LfdDnnJCkCkZpM/yZdqVG3q5Gftm1lGROKxsY/OmBmAdm4xV8XDI3d9ypgo8mq1ODhoWBjwtmjZ9zfY8+q323w7sgQp/n+YU8XdMg6p81P9wDVk85wMezn9GMydXAZ53vTJ+HP9fzC83HujwEH3cYmgQt1MBnTqKjeSQHo/7h/xvEEPONmCfvcc85/Y7SjAAAAABJRU5ErkJggg=='),
  VpnInfo('ExpressVPN', 'com.expressvpn.vpn', 'https://www.expressvpn.com/sign-in', 'Simple and reliable. The TV app signs in with your email.',
      'iVBORw0KGgoAAAANSUhEUgAAARgAAAEYAQAAAACv9dQhAAABJ0lEQVR42u2awQrDMAxDxf7/nzVoLVvODoOx06YOSmZ8eiiyExd8/yA5yUnOxzm4n/qLO2DRB94/v5qD5nhxqdWKhg8vvVw4wJKORcOnSIDCtKiFj/jAdlX4nP4DCtcm9fd8anX8Ur9U1Vex5xmNfsgpW6rumPYp+qHAWKGHusXoRyZU7U9xKkjhsysXuXrF8DHJYOxZwfCh7SzaO/7c/gzMDhtfZvqf6XQwVFo9ZUTxZ0hCsCrfR4+/1w/GcOBGlP5n9MP2ojYfveI/t3x0K7ZFFD7oI/xup3UEi34kon1PpmNG+sNa+S20FfzsL59aNBvmfuzlfl6dEJ1d+PQ8ZxV55H7jmH/BemlmfnHOT+XMsuv4855fwM/vQPick4p8v5Gc5Hwz5wnK+eAoPAt4DwAAAABJRU5ErkJggg=='),
  VpnInfo('Surfshark', 'com.surfshark.vpnclient.android', 'https://my.surfshark.com/', 'One account covers every device in the house.',
      'iVBORw0KGgoAAAANSUhEUgAAAPgAAAD4AQAAAADpqhamAAAA2klEQVR42u2ZSw6EMAxDrbn/nTNCjZ0yC/bDa5FaSFb5OW5QPS8d/dG/XK+1rg8tWST10fP6d73io+zaJQz7r3P2kdDsb/Op9s8Js9+oV0kDVP332/ag8D+9MJGfhal/9/+VCfEMIv7d9EODVhoIY3/tmdC2dyfk4H8lGXY5BP+m6lUDBMD4yxcAcerfnL8C/6sVgvivaf/kAuv+98v8woRQ/K+m8VtB4v8zACHif2Ofc4CFf7rVPqz+7/Y7+OLF353PPqDNf5UuILsBNf/ZIJA4/zn/h46epv8CApCDP1LgMOYAAAAASUVORK5CYII='),
  VpnInfo('Proton VPN', 'ch.protonvpn.android', 'https://account.protonvpn.com/login', 'From the makers of Proton Mail. Has a free plan.',
      'iVBORw0KGgoAAAANSUhEUgAAARgAAAEYAQAAAACv9dQhAAABJUlEQVR42u2aywrDMAwEl/7/P6sk1mOdFgKFXtpxDzVCp0Faee0o7pfIIYecj3O01rE59kdMFo2H7tev5qg5nlROQIotCp+uGqucicKnSSw22XXweeWTkYDPG/1JjVaJEfqTMNSK4z/ml3WTj7ATjoXpr0Wkx1dOevh0/ZQ897ZPifApBVqbsGN0Bv+ezwhyIypM8EkSWTXqI+LoNHzKcI0e+QCDTxLRDK0+GMEnNu9Vc74OjPDp8unGSvkp68F8N/s1fkycf8a/R7hS78Oe+hkd0mg1fMx/qS+ezdNnp1E/JkGmQcWK+596vxhAaocKH8VFmnvP/er1/cJNmLhf3fiM2fCmg8/+/iVHRP1s76c51cd6UT/WSvOEYX/w4fsNcsj5Us4TJuHkJK/5pOgAAAAASUVORK5CYII='),
  VpnInfo('CyberGhost', 'de.mobileconcepts.cyberghost', 'https://my.cyberghostvpn.com/', 'Has servers set up for streaming.',
      'iVBORw0KGgoAAAANSUhEUgAAARgAAAEYAQAAAACv9dQhAAABKUlEQVR42u2awQoCQQxDi///zxXXJqnuYUHwom8UnC29bOg0acbq61XkkEPOxzn1XMfu8T0CK3qr6/WrOWUcqweUx25FweeApad02rGJgo+RqNRRg88Zn+lA+gGf1/4jZHrjBT5mqrcP/DXvH7JPdMf/Hp8a3eO+E8DAx4wlgldnthKiflJAUd2J0Z9rHSx3n4K/wl8zXIxAlA6Cvzx7tSbTbBt9mPrpJRY9vzf1s/qPCkfMrgfOVy9yV/F4FgOfFh4Vi8wDGfjE/1nUZScIfE4De8VnBR9ZGzI3dMbQz+/zewRQTDL46/X+ouTTdyZ5+rMYPsZPrUkVfNZMWr7F8PEDH3s9m+A5Xyd8LIOsD+nPq//k5ms9gY9322Ft26voH/6/QQ45X8m5A2EVzjoj+r4YAAAAAElFTkSuQmCC'),
  VpnInfo('Private Internet Access', 'com.privateinternetaccess.android', 'https://www.privateinternetaccess.com/account/client-control-panel', 'Budget friendly with lots of settings.',
      'iVBORw0KGgoAAAANSUhEUgAAAVgAAAFYAQAAAAA+F9ntAAABzElEQVR42u2by27DMAwEif7/P7MIJC7XaQ+BqJ46dg62pdOAWC0fifz8Cvayl73/bm+sa729Hl6/WrPVr/j8Yu+D6ma77oV3kbVV+B7zXUhX1O4gNrIbOHynfPXW8RvwvRi/JQr1ORO+9/Q3FLwS4k0W/R3xDSnBbzf+YchXXq1VeGHPxzJ8J/obkW/erHlvzDA7jN+CujVYLk1LS4Rhdny+lWXYh9kjkCUUMDs+32QflF/r5GtBhtm5PqR5MQtc2Qf4TvgqERbqSjPQ3yv+LKwGsfQg+jP6O+VbaVtFq1vf9sgwO9aHH05iGzXFNHyH55tV20sW2gbD90b9odKLCPPDW43R31l+rChtBc5O7fC/4/pOpRISXKtBUH+Y+zPrCoVndF0ghu+5PhTg9F7cI4zhO+wPdRPDUrpHugGz8/zCqute/7UQhu+svp5+pFl3s2MaZiP9DWepKMb/XvO/GVYFlk70vBXMBv35Lkqm5W7WW4bvvH/sqDtvq2eYTesPLbZq0if+4dr8zps5I37/Zn7SasJh7Qv4zvl2001VyiYPsxvzqWmN5PIW5Mf35tdt8KHnVonfG/OT1r1Im/Rj/uGO/+U/QexlL3v9+gYfPG411X8nQwAAAABJRU5ErkJggg=='),
  VpnInfo('Mullvad', 'net.mullvad.mullvadvpn', 'https://mullvad.net/en/account/login', 'Private by design: no email needed, just an account number.',
      'iVBORw0KGgoAAAANSUhEUgAAARgAAAEYAQAAAACv9dQhAAABKklEQVR42u2awQ7CMAxDI/7/nw2jjetOkyYhcYE3DmxRLjyljpNRur+KHHLI+TinxvW6jzvfS4+6v341p8xxUNEROeA4Cp93rcyK6aIrR+FjEu/HQQk+V/UzEI0wfM76o45MhUZ/Jp/sWutD/5q//8IVbGHOl1xBsji3AsFnyrBRtQANxYZPKQTIXWt5xL/Xn64c2To7zvkapeJ+FTVFfzeLkwDR30/nK0/UNM5lbtRPD6U9W6hnMfiE/zktjPyM/1F8eZAX/if51DahNh3O13KEE5OtUEsRfJQtS2mG4BOCXJsIqdDnff/TzmcbMuDj9xdpnpefhk/vn1fPqmhk8DGfNarmIhE+vTvsXZDXiMyn+f4iV4nxupD+VZUje4U3pH/x/w1yyPlWzhNHBsw8IvgVlQAAAABJRU5ErkJggg=='),
  VpnInfo('Tailscale', 'com.tailscale.ipn', 'https://login.tailscale.com/admin', 'Reach your home network (Plex, servers) from anywhere.',
      'iVBORw0KGgoAAAANSUhEUgAAARgAAAEYAQAAAACv9dQhAAABKUlEQVR42u2a2wrDMAxDzf7/nzW6+KJkg8JgL+OkG2WpXypkWXYWul9BDDHEfB0Ta1135U/blR5xv/41JhrHuD4XSK+b7YLPiznFn0Wl2QWfQSKieQQ+H/BZ9ElVAp9DfxIj0yD0Z6tf+0X9yvffy/3bHvwpbW4ebUINfxYeSZ70iLkFPpKZn+ROG2n4o7Y7BU77oCIX+dVoZIehfgR/VOyRmR7059Bnb+LDWn/w2ZIr6iuNDaJ+RXTjVc270J/JrxScPcvaS8OfmBSzKVkJN/wZ+9wtvAkQ/PESJuveF1rwZ5r3bUJGf3HOf6wPmyk9/tlOemSTepFf5/y55z9V58HHzy+KOwUS+eXnX1bG3ESDz5yfdn23A2rql7Xux8wM/vD/DWKI+VXME40I4CjFQEJoAAAAAElFTkSuQmCC'),
  VpnInfo('OpenVPN Connect', 'net.openvpn.openvpn', 'https://openvpn.net/client/', 'For a VPN your work or your own server gives you as a .ovpn file.',
      'iVBORw0KGgoAAAANSUhEUgAAARgAAAEYAQAAAACv9dQhAAABLElEQVR42u2a0QrCUAxDg///z5XtNkl3FQbik2aCbpc+Hdqk7UTdX0hMYhLzcQzW1c/HzfHk0wfur1+NgTjihKMvn4bPypf+7YTSafiIBEgEqPB5lz8nmmYUPpv+rMfW5uiP+fTd9ol/ydVp9n2yNQZ/z6ddHWqJVjrxJPVlTCZDHQof6k3BDiY7Cx+7FfsfdAe0ho3waVGGBrKS7YcPC2o00E2Gt/EvsKhkYbT58KmpN8UOCB40wodKrHLz0JH8UXlNLHK18KlZYV6PVfTnslUtL35gec58QfWRBI1BI/3zZX6fhDx3hA+cLFqOYTTRmU+15Ggvu/TV4UMvv645VGzho7l95JNn1PDxXqO4CRqLs/DZ3YuUUl8v79/9Giz6vL+/yP83EpOYr8Y8AfMw4ScVZU+rAAAAAElFTkSuQmCC'),
  VpnInfo('WireGuard', 'com.wireguard.android', 'https://www.wireguard.com/install/', 'For WireGuard configs from your router or server.',
      'iVBORw0KGgoAAAANSUhEUgAAARgAAAEYAQAAAACv9dQhAAABLElEQVR42u2azQoCQQyDg+//zhV3+pPZFRYEL/qNeOjQi6FJ2o6K+yNyyCHn4xytE8f3FUZGx23EQ/fnV3PUOC5UDnhW1PiBT1bOqh4tdOYWfBYSUpNOAT7X+jGyUT9X/TFcFOjP4FP+tX/wr/z94/V5o70zgF9byzP8SskGn9GhMi6/g1+rgKI6n4zK8f8eH0fnxC3qx9S5hDn7ngrBJ+GowSIHjRw20Geb1rW5PPgovIFO42rNDvR5tKdJVeJcMkT9mHkNUEUv9Cem17H66RkVfqUee2TLDvg1neEM7oMe9TPze6j9PdhvnPY/2jer+Ne794tRniou8FHbVTuXtYrgI9vH96DRDTT4+OTVvFK9EoLPjF9hPWOgz2f/sj39PDLT//D/DXLI+UbOE/bP0DhrpIreAAAAAElFTkSuQmCC'),
];
